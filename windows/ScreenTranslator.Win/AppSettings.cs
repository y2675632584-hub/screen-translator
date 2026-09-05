using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace ScreenTranslator.Win;

internal sealed class AppSettings
{
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenTranslator");
    private static readonly string SettingsPath = Path.Combine(DirectoryPath, "settings.json");
    private static readonly string KeyPath = Path.Combine(DirectoryPath, "openai-key.bin");
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunName = "ScreenTranslator";

    public string HotKey { get; set; } = "F8";
    public string Mode { get; set; } = "live";
    public string SourceLanguage { get; set; } = "auto";
    public string TargetLanguage { get; set; } = "zh-Hans";
    public string Model { get; set; } = "gpt-5-mini";
    public float FontScale { get; set; } = 1f;
    public bool LaunchAtLogin { get; set; }

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath)) ?? new();
        }
        catch { }
        return new();
    }

    public void Save()
    {
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        if (LaunchAtLogin)
            key?.SetValue(RunName, $"\"{Application.ExecutablePath}\" --background");
        else
            key?.DeleteValue(RunName, throwOnMissingValue: false);
    }

    public static string LoadApiKey()
    {
        try
        {
            if (!File.Exists(KeyPath)) return "";
            var protectedBytes = File.ReadAllBytes(KeyPath);
            var bytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch { return ""; }
    }

    public static void SaveApiKey(string value)
    {
        Directory.CreateDirectory(DirectoryPath);
        if (string.IsNullOrWhiteSpace(value))
        {
            if (File.Exists(KeyPath)) File.Delete(KeyPath);
            return;
        }
        var bytes = Encoding.UTF8.GetBytes(value.Trim());
        File.WriteAllBytes(KeyPath, ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser));
    }
}

internal sealed record LanguageChoice(string Code, string Name)
{
    public override string ToString() => Name;
}

internal static class LanguageCatalog
{
    public static readonly LanguageChoice[] Targets =
    [
        new("zh-Hans", "简体中文"), new("zh-Hant", "繁体中文"), new("en", "英语"),
        new("ja", "日语"), new("ko", "韩语"), new("fr", "法语"), new("de", "德语"),
        new("es", "西班牙语"), new("it", "意大利语"), new("pt", "葡萄牙语"),
        new("ru", "俄语"), new("ar", "阿拉伯语"), new("th", "泰语"), new("vi", "越南语"),
        new("tr", "土耳其语"), new("pl", "波兰语"), new("nl", "荷兰语"),
        new("uk", "乌克兰语"), new("id", "印度尼西亚语"), new("hi", "印地语")
    ];

    public static IReadOnlyList<LanguageChoice> InstalledOcrLanguages()
    {
        var result = new List<LanguageChoice> { new("auto", "自动识别") };
        try
        {
            foreach (var language in Windows.Media.Ocr.OcrEngine.AvailableRecognizerLanguages)
                result.Add(new(language.LanguageTag, language.DisplayName));
        }
        catch { result.Add(new("en-US", "English (United States)")); }
        return result.GroupBy(x => x.Code, StringComparer.OrdinalIgnoreCase).Select(x => x.First()).ToList();
    }
}
