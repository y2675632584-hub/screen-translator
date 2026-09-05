using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace ScreenTranslator.Win;

internal sealed record TranslatedRegion(Rectangle Bounds, string Text);

internal sealed class OverlayForm : Form
{
    private const int WsExTransparent = 0x20, WsExNoActivate = 0x08000000, WsExToolWindow = 0x80;
    private const uint WdaExcludeFromCapture = 0x11;
    private IReadOnlyList<TranslatedRegion> _regions = [];
    private float _fontScale = 1f;

    public OverlayForm(Screen screen)
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Bounds = screen.Bounds;
        TopMost = true;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        DoubleBuffered = true;
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= WsExTransparent | WsExNoActivate | WsExToolWindow; return value; }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        SetWindowDisplayAffinity(Handle, WdaExcludeFromCapture);
    }

    public void ShowRegions(IReadOnlyList<TranslatedRegion> regions, float fontScale)
    {
        _regions = regions; _fontScale = fontScale; Invalidate();
        if (!Visible) Show();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        foreach (var region in _regions)
        {
            var box = Rectangle.Inflate(region.Bounds, 3, 2);
            using var path = RoundedRectangle(box, Math.Min(8, Math.Max(3, box.Height / 4)));
            using var background = new SolidBrush(Color.FromArgb(32, 36, 46));
            e.Graphics.FillPath(background, path);
            var size = Math.Clamp(region.Bounds.Height * 0.72f * _fontScale, 10f, 28f);
            using var font = new Font("Microsoft YaHei UI", size, FontStyle.Regular, GraphicsUnit.Pixel);
            TextRenderer.DrawText(e.Graphics, region.Text, font, region.Bounds, Color.White,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        var diameter = radius * 2; var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure(); return path;
    }

    [DllImport("user32.dll")] private static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint affinity);
}
