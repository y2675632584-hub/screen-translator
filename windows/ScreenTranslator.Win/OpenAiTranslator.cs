using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace ScreenTranslator.Win;

internal sealed class OpenAiTranslator
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(20) };

    public async Task<Dictionary<string, string>> TranslateAsync(
        IReadOnlyList<OcrRegion> regions,
        string sourceLanguage,
        string targetLanguage,
        string apiKey,
        string model,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(apiKey)) throw new InvalidOperationException("请先在设置中填写 OpenAI API Key。");
        var items = regions.Take(120).Select(x => new { id = x.Id, text = x.Text }).ToArray();
        var schema = new
        {
            type = "object",
            properties = new
            {
                translations = new
                {
                    type = "array",
                    items = new
                    {
                        type = "object",
                        properties = new { id = new { type = "string" }, text = new { type = "string" } },
                        required = new[] { "id", "text" },
                        additionalProperties = false
                    }
                }
            },
            required = new[] { "translations" },
            additionalProperties = false
        };
        var body = new
        {
            model,
            store = false,
            instructions = $"Translate screen text from {(sourceLanguage == "auto" ? "automatically detected languages" : sourceLanguage)} to {targetLanguage}. Use nearby items as context. Preserve names, numbers, shortcuts and UI tone. If an item is already in the target language, return its original text. Return every id exactly once.",
            input = JsonSerializer.Serialize(items),
            text = new { format = new { type = "json_schema", name = "screen_translations", strict = true, schema } }
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        using var response = await Client.SendAsync(request, cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            try
            {
                var error = JsonDocument.Parse(content).RootElement.GetProperty("error").GetProperty("message").GetString();
                throw new InvalidOperationException($"OpenAI 请求失败：{error}");
            }
            catch (JsonException) { throw new InvalidOperationException($"OpenAI 请求失败：{(int)response.StatusCode}"); }
        }
        using var document = JsonDocument.Parse(content);
        var outputText = FindOutputText(document.RootElement) ?? throw new InvalidOperationException("OpenAI 没有返回译文。");
        using var translated = JsonDocument.Parse(outputText);
        return translated.RootElement.GetProperty("translations").EnumerateArray()
            .Where(x => x.TryGetProperty("id", out _) && x.TryGetProperty("text", out _))
            .ToDictionary(x => x.GetProperty("id").GetString() ?? "", x => x.GetProperty("text").GetString() ?? "");
    }

    private static string? FindOutputText(JsonElement root)
    {
        if (!root.TryGetProperty("output", out var output)) return null;
        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("content", out var contents)) continue;
            foreach (var content in contents.EnumerateArray())
                if (content.TryGetProperty("type", out var type) && type.GetString() == "output_text" && content.TryGetProperty("text", out var text))
                    return text.GetString();
        }
        return null;
    }
}
