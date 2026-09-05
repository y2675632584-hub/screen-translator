namespace ScreenTranslator.Win;

internal sealed class SettingsForm : Form
{
    private readonly TranslatorApplicationContext _app;
    private readonly ComboBox _mode = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _source = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _target = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox _model = new();
    private readonly TextBox _apiKey = new() { UseSystemPasswordChar = true };
    private readonly CheckBox _launch = new() { Text = "开机后在后台启动", AutoSize = true };
    private readonly TrackBar _fontScale = new() { Minimum = 80, Maximum = 140, TickFrequency = 10, SmallChange = 10 };
    private readonly Label _fontValue = new() { AutoSize = true };
    private readonly Label _status = new() { AutoSize = false, ForeColor = Color.DimGray, Height = 44, Dock = DockStyle.Fill };
    private readonly Button _shortcut = new();
    private bool _recording;

    public SettingsForm(TranslatorApplicationContext app)
    {
        _app = app;
        Text = "屏幕译";
        ClientSize = new Size(560, 650);
        MinimumSize = new Size(560, 650);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;
        Font = new Font("Microsoft YaHei UI", 9f);
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        _mode.Items.AddRange(["实时翻译", "单次翻译"]);
        _source.Items.AddRange(LanguageCatalog.InstalledOcrLanguages().Cast<object>().ToArray());
        _target.Items.AddRange(LanguageCatalog.Targets.Cast<object>().ToArray());
        _fontScale.ValueChanged += (_, _) => _fontValue.Text = $"{_fontScale.Value}%";
        _shortcut.Click += (_, _) => BeginRecording();
        KeyDown += CaptureShortcut;
        FormClosing += (_, e) => { e.Cancel = true; Hide(); if (_recording) EndRecording(false); };
        _app.StateChanged += UpdateStatus;

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(28), ColumnCount = 1, RowCount = 4 };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(Header(), 0, 0);
        root.Controls.Add(new Label { Text = "Windows 本机识别文字，AI 仅接收识别后的文本，不上传屏幕截图。", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(0, 8, 0, 18) }, 0, 1);
        root.Controls.Add(SettingsPanel(), 0, 2);
        root.Controls.Add(Footer(), 0, 3);
        Controls.Add(root);
        LoadValues();
    }

    private Control Header()
    {
        var panel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png");
        if (File.Exists(iconPath)) panel.Controls.Add(new PictureBox { Image = Image.FromFile(iconPath), SizeMode = PictureBoxSizeMode.Zoom, Size = new Size(56, 56), Margin = new Padding(0, 0, 14, 0) });
        var text = new TableLayoutPanel { AutoSize = true, RowCount = 2 };
        text.Controls.Add(new Label { Text = "屏幕译", Font = new Font(Font.FontFamily, 19, FontStyle.Bold), AutoSize = true }, 0, 0);
        text.Controls.Add(new Label { Text = "按一下显示译文，再按一下回到原文", AutoSize = true, ForeColor = Color.DimGray }, 0, 1);
        panel.Controls.Add(text); return panel;
    }

    private Control SettingsPanel()
    {
        var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoScroll = true };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 36));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 64));
        AddRow(grid, "切换快捷键", _shortcut);
        AddRow(grid, "翻译模式", _mode);
        AddRow(grid, "原文语言", _source);
        AddRow(grid, "翻译成", _target);
        AddRow(grid, "AI 模型", _model);
        var keyPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoSize = true };
        keyPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); keyPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        keyPanel.Controls.Add(_apiKey, 0, 0);
        var clear = new Button { Text = "移除", AutoSize = true }; clear.Click += (_, _) => { _app.ClearApiKey(); _apiKey.Clear(); };
        keyPanel.Controls.Add(clear, 1, 0);
        AddRow(grid, "OpenAI API Key", keyPanel);
        var scalePanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoSize = true };
        scalePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); scalePanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        scalePanel.Controls.Add(_fontScale, 0, 0); scalePanel.Controls.Add(_fontValue, 1, 0);
        AddRow(grid, "译文字号", scalePanel);
        AddRow(grid, "", _launch);
        var helpRow = grid.RowCount++;
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var help = new Label
        {
            Text = "提示：可识别语言来自 Windows 已安装的 OCR 语言包。API Key 使用当前 Windows 账户加密保存。",
            AutoSize = true,
            ForeColor = Color.DimGray,
            MaximumSize = new Size(460, 0),
            Margin = new Padding(0, 14, 0, 0)
        };
        grid.Controls.Add(help, 0, helpRow);
        grid.SetColumnSpan(help, 2);
        return grid;
    }

    private Control Footer()
    {
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 2, Margin = new Padding(0, 18, 0, 0) };
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        footer.Controls.Add(_status, 0, 0);
        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        var save = new Button { Text = "保存设置", AutoSize = true }; save.Click += (_, _) => SaveValues();
        var toggle = new Button { Text = "开启／关闭翻译", AutoSize = true }; toggle.Click += (_, _) => _app.Toggle();
        buttons.Controls.Add(save); buttons.Controls.Add(toggle); footer.Controls.Add(buttons, 1, 0); return footer;
    }

    private static void AddRow(TableLayoutPanel grid, string label, Control control)
    {
        var row = grid.RowCount++;
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 10, 8, 10) }, 0, row);
        control.Dock = DockStyle.Fill; control.Margin = new Padding(0, 5, 0, 5); grid.Controls.Add(control, 1, row);
    }

    private void LoadValues()
    {
        var settings = _app.Settings;
        _shortcut.Text = settings.HotKey;
        _mode.SelectedIndex = settings.Mode == "single" ? 1 : 0;
        SelectLanguage(_source, settings.SourceLanguage);
        SelectLanguage(_target, settings.TargetLanguage);
        _model.Text = settings.Model;
        _launch.Checked = settings.LaunchAtLogin;
        _fontScale.Value = Math.Clamp((int)(settings.FontScale * 100), 80, 140);
        _apiKey.PlaceholderText = string.IsNullOrEmpty(AppSettings.LoadApiKey()) ? "粘贴 API Key" : "已安全保存；留空保持不变";
        UpdateStatus();
    }

    private void SaveValues()
    {
        var settings = _app.Settings;
        settings.Mode = _mode.SelectedIndex == 1 ? "single" : "live";
        settings.SourceLanguage = (_source.SelectedItem as LanguageChoice)?.Code ?? "auto";
        settings.TargetLanguage = (_target.SelectedItem as LanguageChoice)?.Code ?? "zh-Hans";
        settings.Model = string.IsNullOrWhiteSpace(_model.Text) ? "gpt-5-mini" : _model.Text.Trim();
        settings.LaunchAtLogin = _launch.Checked;
        settings.FontScale = _fontScale.Value / 100f;
        _app.ApplySettings(_apiKey.Text);
        _apiKey.Clear(); _apiKey.PlaceholderText = "已安全保存；留空保持不变";
        UpdateStatus();
    }

    private void BeginRecording()
    {
        _recording = true; _app.SuspendHotKey(); _shortcut.Text = "请按下新快捷键…"; _shortcut.Focus();
    }

    private void CaptureShortcut(object? sender, KeyEventArgs e)
    {
        if (!_recording || e.KeyCode is Keys.ControlKey or Keys.ShiftKey or Keys.Menu or Keys.LWin or Keys.RWin) return;
        e.SuppressKeyPress = true;
        var value = GlobalHotKey.Describe(e.KeyCode, e.Modifiers);
        if (_app.TrySetHotKey(value)) { _shortcut.Text = value; EndRecording(true); }
        else { _status.Text = "该按键已被系统或其他软件占用，请换一个。"; _shortcut.Text = _app.Settings.HotKey; EndRecording(false); }
    }

    private void EndRecording(bool registered)
    {
        _recording = false;
        if (!registered) _app.RestoreHotKey();
    }

    private void UpdateStatus()
    {
        if (IsDisposed) return;
        if (InvokeRequired) { BeginInvoke(UpdateStatus); return; }
        _status.Text = _app.Status;
    }

    private static void SelectLanguage(ComboBox combo, string code)
    {
        for (var i = 0; i < combo.Items.Count; i++)
            if (combo.Items[i] is LanguageChoice choice && choice.Code.Equals(code, StringComparison.OrdinalIgnoreCase)) { combo.SelectedIndex = i; return; }
        if (combo.Items.Count > 0) combo.SelectedIndex = 0;
    }
}
