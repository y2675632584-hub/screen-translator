using System.Runtime.InteropServices;

namespace ScreenTranslator.Win;

internal sealed class GlobalHotKey : NativeWindow, IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModAlt = 0x0001, ModControl = 0x0002, ModShift = 0x0004, ModWin = 0x0008, ModNoRepeat = 0x4000;
    private const int HotKeyId = 0x5343;
    private bool _registered;
    public event Action? Pressed;

    public GlobalHotKey() => CreateHandle(new CreateParams { Caption = "ScreenTranslatorHotKey" });

    public bool Register(string description)
    {
        Unregister();
        if (!TryParse(description, out var modifiers, out var key)) return false;
        _registered = RegisterHotKey(Handle, HotKeyId, modifiers | ModNoRepeat, (uint)key);
        return _registered;
    }

    public void Unregister()
    {
        if (_registered) UnregisterHotKey(Handle, HotKeyId);
        _registered = false;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotKey && m.WParam.ToInt32() == HotKeyId) Pressed?.Invoke();
        base.WndProc(ref m);
    }

    public static string Describe(Keys key, Keys modifiers)
    {
        var parts = new List<string>();
        if (modifiers.HasFlag(Keys.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(Keys.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(Keys.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(Keys.LWin) || modifiers.HasFlag(Keys.RWin)) parts.Add("Win");
        parts.Add(key.ToString());
        return string.Join("+", parts);
    }

    private static bool TryParse(string value, out uint modifiers, out Keys key)
    {
        modifiers = 0; key = Keys.None;
        foreach (var part in value.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (part.Equals("Ctrl", StringComparison.OrdinalIgnoreCase)) modifiers |= ModControl;
            else if (part.Equals("Alt", StringComparison.OrdinalIgnoreCase)) modifiers |= ModAlt;
            else if (part.Equals("Shift", StringComparison.OrdinalIgnoreCase)) modifiers |= ModShift;
            else if (part.Equals("Win", StringComparison.OrdinalIgnoreCase)) modifiers |= ModWin;
            else if (!Enum.TryParse(part, true, out key)) return false;
        }
        return key is not Keys.None and not Keys.ControlKey and not Keys.ShiftKey and not Keys.Menu;
    }

    public void Dispose() { Unregister(); DestroyHandle(); }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
