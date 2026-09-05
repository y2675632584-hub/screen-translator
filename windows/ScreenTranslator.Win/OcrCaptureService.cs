using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using WinRect = Windows.Foundation.Rect;

namespace ScreenTranslator.Win;

internal sealed record OcrRegion(string Id, string Text, Rectangle Bounds);
internal sealed record CapturedFrame(byte[] Fingerprint, IReadOnlyList<OcrRegion> Regions);

internal sealed class OcrCaptureService
{
    public async Task<CapturedFrame> CaptureAsync(Screen screen, string sourceLanguage, CancellationToken cancellationToken)
    {
        using var original = new Bitmap(screen.Bounds.Width, screen.Bounds.Height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(original))
            graphics.CopyFromScreen(screen.Bounds.Location, System.Drawing.Point.Empty, screen.Bounds.Size, CopyPixelOperation.SourceCopy);

        cancellationToken.ThrowIfCancellationRequested();
        var fingerprint = MakeFingerprint(original);
        var maximum = (int)OcrEngine.MaxImageDimension;
        var ratio = Math.Min(1d, maximum / (double)Math.Max(original.Width, original.Height));
        using var prepared = ratio < 1
            ? new Bitmap(original, new System.Drawing.Size((int)(original.Width * ratio), (int)(original.Height * ratio)))
            : new Bitmap(original);
        using var softwareBitmap = ToSoftwareBitmap(prepared);

        OcrEngine? engine;
        if (sourceLanguage == "auto")
            engine = OcrEngine.TryCreateFromUserProfileLanguages();
        else
            engine = OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language(sourceLanguage));
        if (engine is null)
            throw new InvalidOperationException("所选 OCR 语言尚未安装，请在 Windows 语言设置中添加对应语言包。");

        var result = await engine.RecognizeAsync(softwareBitmap);
        cancellationToken.ThrowIfCancellationRequested();
        var regions = new List<OcrRegion>();
        var index = 0;
        foreach (var line in result.Lines)
        {
            var words = line.Words;
            if (words.Count == 0 || string.IsNullOrWhiteSpace(line.Text)) continue;
            WinRect union = words[0].BoundingRect;
            foreach (var word in words.Skip(1)) union = Union(union, word.BoundingRect);
            var bounds = new Rectangle(
                (int)Math.Round(union.X / ratio), (int)Math.Round(union.Y / ratio),
                Math.Max(1, (int)Math.Round(union.Width / ratio)), Math.Max(1, (int)Math.Round(union.Height / ratio)));
            regions.Add(new OcrRegion((index++).ToString(), line.Text.Trim(), bounds));
        }
        return new(fingerprint, regions);
    }

    public static bool IsMeaningfullyDifferent(byte[]? previous, byte[] current)
    {
        if (previous is null || previous.Length != current.Length) return true;
        var changed = 0;
        var total = 0;
        for (var i = 0; i < current.Length; i++)
        {
            var difference = Math.Abs(previous[i] - current[i]);
            total += difference;
            if (difference >= 20) changed++;
        }
        return changed / (double)current.Length >= 0.008 || total / (double)current.Length >= 1.8;
    }

    private static byte[] MakeFingerprint(Bitmap source)
    {
        using var sample = new Bitmap(source, new System.Drawing.Size(80, 45));
        var data = sample.LockBits(new Rectangle(0, 0, sample.Width, sample.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var raw = new byte[Math.Abs(data.Stride) * sample.Height];
            Marshal.Copy(data.Scan0, raw, 0, raw.Length);
            var result = new byte[sample.Width * sample.Height];
            for (var y = 0; y < sample.Height; y++)
            for (var x = 0; x < sample.Width; x++)
            {
                var offset = y * Math.Abs(data.Stride) + x * 4;
                result[y * sample.Width + x] = (byte)((raw[offset] * 11 + raw[offset + 1] * 59 + raw[offset + 2] * 30) / 100);
            }
            return result;
        }
        finally { sample.UnlockBits(data); }
    }

    private static SoftwareBitmap ToSoftwareBitmap(Bitmap bitmap)
    {
        var software = new SoftwareBitmap(BitmapPixelFormat.Bgra8, bitmap.Width, bitmap.Height, BitmapAlphaMode.Premultiplied);
        var source = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            using var destination = software.LockBuffer(BitmapBufferAccessMode.Write);
            using var reference = destination.CreateReference();
            ((IMemoryBufferByteAccess)reference).GetBuffer(out var pointer, out _);
            var plane = destination.GetPlaneDescription(0);
            var sourceStride = Math.Abs(source.Stride);
            var row = new byte[bitmap.Width * 4];
            for (var y = 0; y < bitmap.Height; y++)
            {
                Marshal.Copy(IntPtr.Add(source.Scan0, y * sourceStride), row, 0, row.Length);
                Marshal.Copy(row, 0, IntPtr.Add(pointer, plane.StartIndex + y * plane.Stride), row.Length);
            }
        }
        finally { bitmap.UnlockBits(source); }
        return software;
    }

    private static WinRect Union(WinRect a, WinRect b)
    {
        var left = Math.Min(a.X, b.X); var top = Math.Min(a.Y, b.Y);
        var right = Math.Max(a.X + a.Width, b.X + b.Width); var bottom = Math.Max(a.Y + a.Height, b.Y + b.Height);
        return new WinRect(left, top, right - left, bottom - top);
    }

    [ComImport, Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMemoryBufferByteAccess
    {
        void GetBuffer(out IntPtr buffer, out uint capacity);
    }
}
