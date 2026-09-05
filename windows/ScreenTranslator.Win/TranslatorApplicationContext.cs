using System.Runtime.InteropServices;

namespace ScreenTranslator.Win;

internal sealed class TranslatorApplicationContext : ApplicationContext
{
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly GlobalHotKey _hotKey = new();
    private readonly OcrCaptureService _capture = new();
    private readonly OpenAiTranslator _translator = new();
    private readonly NotifyIcon _tray;
    private readonly ToolStripMenuItem _toggleItem;
    private readonly ToolStripMenuItem _statusItem;
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 850 };
    private readonly Dictionary<string, string> _cache = new();
    private SettingsForm? _settingsForm;
    private OverlayForm? _overlay;
    private Screen? _screen;
    private CancellationTokenSource? _cancellation;
    private byte[]? _fingerprint;
    private bool _active;
    private bool _processing;
    private int _generation;

    public AppSettings Settings => _settings;
    public string Status { get; private set; } = "准备就绪";
    public event Action? StateChanged;

    public TranslatorApplicationContext()
    {
        _toggleItem = new ToolStripMenuItem("开启翻译", null, (_, _) => Toggle());
        _statusItem = new ToolStripMenuItem(Status) { Enabled = false };
        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("屏幕译", null, (_, _) => ShowSettings()) { Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Bold) });
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_toggleItem);
        menu.Items.Add(new ToolStripMenuItem("设置…", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("退出", null, (_, _) => Exit()));
        _tray = new NotifyIcon
        {
            Text = "屏幕译",
            Icon = LoadIcon(),
            ContextMenuStrip = menu,
            Visible = true
        };
        _tray.DoubleClick += (_, _) => ShowSettings();
        _timer.Tick += async (_, _) => await ProcessFrameAsync();
        _hotKey.Pressed += Toggle;
        if (!_hotKey.Register(_settings.HotKey))
        {
            _settings.HotKey = "Ctrl+Shift+F8";
            _hotKey.Register(_settings.HotKey);
            _settings.Save();
            SetStatus("原快捷键被占用，已改为 Ctrl+Shift+F8");
        }
        if (!Environment.GetCommandLineArgs().Contains("--background")) ShowSettings();
    }

    public void Toggle()
    {
        if (_active) Stop(); else Start();
    }

    private void Start()
    {
        if (string.IsNullOrWhiteSpace(AppSettings.LoadApiKey()))
        {
            SetStatus("请先在设置中填写 OpenAI API Key"); ShowSettings(); return;
        }
        _generation++;
        _cancellation = new CancellationTokenSource();
        _screen = Screen.FromPoint(Cursor.Position);
        _overlay = new OverlayForm(_screen);
        _fingerprint = null;
        _cache.Clear();
        _active = true;
        _toggleItem.Text = $"关闭翻译（{_settings.HotKey}）";
        SetStatus("正在读取屏幕…");
        _timer.Start();
        _ = ProcessFrameAsync();
    }

    public void Stop(string? message = null)
    {
        _active = false; _generation++;
        _timer.Stop();
        _cancellation?.Cancel(); _cancellation?.Dispose(); _cancellation = null;
        _overlay?.Close(); _overlay?.Dispose(); _overlay = null;
        _fingerprint = null; _cache.Clear();
        _toggleItem.Text = $"开启翻译（{_settings.HotKey}）";
        SetStatus(message ?? $"已关闭，按 {_settings.HotKey} 开始");
    }

    private async Task ProcessFrameAsync()
    {
        if (!_active || _processing || _screen is null || _overlay is null || _cancellation is null) return;
        _processing = true;
        var generation = _generation;
        try
        {
            var frame = await _capture.CaptureAsync(_screen, _settings.SourceLanguage, _cancellation.Token);
            if (!_active || generation != _generation) return;
            if (!OcrCaptureService.IsMeaningfullyDifferent(_fingerprint, frame.Fingerprint)) return;
            _fingerprint = frame.Fingerprint;
            var visible = frame.Regions.Where(x => !string.IsNullOrWhiteSpace(x.Text)).Take(120).ToList();
            var missing = visible.Where(x => !_cache.ContainsKey(CacheKey(x.Text))).ToList();
            if (missing.Count > 0)
            {
                var translated = await _translator.TranslateAsync(missing, _settings.SourceLanguage,
                    _settings.TargetLanguage, AppSettings.LoadApiKey(), _settings.Model, _cancellation.Token);
                if (!_active || generation != _generation) return;
                foreach (var region in missing)
                    if (translated.TryGetValue(region.Id, out var value)) _cache[CacheKey(region.Text)] = value;
            }
            var overlays = visible.Select(x => new { Region = x, Text = _cache.GetValueOrDefault(CacheKey(x.Text)) })
                .Where(x => !string.IsNullOrWhiteSpace(x.Text) && !string.Equals(x.Text, x.Region.Text, StringComparison.OrdinalIgnoreCase))
                .Select(x => new TranslatedRegion(x.Region.Bounds, x.Text!)).ToList();
            _overlay.ShowRegions(overlays, _settings.FontScale);
            SetStatus(overlays.Count == 0 ? "未发现需要翻译的文字" : $"已翻译 {overlays.Count} 处文字 · {_settings.HotKey} 关闭");
            if (_settings.Mode == "single") _timer.Stop();
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (_active && generation == _generation) SetStatus(error.Message);
        }
        finally
        {
            _processing = false;
        }
    }

    private string CacheKey(string text) => $"{_settings.SourceLanguage}\0{_settings.TargetLanguage}\0{text}";

    public bool TrySetHotKey(string value)
    {
        _hotKey.Unregister();
        if (_hotKey.Register(value))
        {
            _settings.HotKey = value; _settings.Save(); Stop($"快捷键已设置为 {value}"); return true;
        }
        _hotKey.Register(_settings.HotKey);
        return false;
    }

    public void SuspendHotKey() => _hotKey.Unregister();
    public void RestoreHotKey() => _hotKey.Register(_settings.HotKey);

    public void ApplySettings(string apiKey)
    {
        if (!string.IsNullOrWhiteSpace(apiKey)) AppSettings.SaveApiKey(apiKey);
        _settings.Save();
        Stop("设置已保存");
    }

    public void ClearApiKey() { AppSettings.SaveApiKey(""); SetStatus("API Key 已从本机移除"); }

    public void ShowSettings()
    {
        if (_settingsForm is null || _settingsForm.IsDisposed) _settingsForm = new SettingsForm(this);
        _settingsForm.Show(); _settingsForm.Activate();
    }

    private void SetStatus(string value)
    {
        Status = value;
        _statusItem.Text = value.Length > 72 ? value[..72] + "…" : value;
        _tray.Text = value.Length > 63 ? value[..63] : value;
        StateChanged?.Invoke();
    }

    private void Exit()
    {
        Stop(); _tray.Visible = false; _tray.Dispose(); _hotKey.Dispose(); _timer.Dispose(); ExitThread();
    }

    private static Icon LoadIcon()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png");
            using var bitmap = new Bitmap(path);
            var handle = bitmap.GetHicon();
            try { return (Icon)Icon.FromHandle(handle).Clone(); }
            finally { DestroyIcon(handle); }
        }
        catch { return SystemIcons.Application; }
    }

    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);
}
