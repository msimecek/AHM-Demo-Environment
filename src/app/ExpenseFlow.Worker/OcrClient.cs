using System.Net.Http.Json;
using ExpenseFlow.Shared;

namespace ExpenseFlow.Worker;

public sealed class OcrClient(HttpClient httpClient)
{
    public async Task<OcrResult> ExtractAsync(ExpenseSubmittedMessage message, CancellationToken cancellationToken)
    {
        var options = ExpenseFlowOptions.FromEnvironment();
        httpClient.BaseAddress ??= new Uri(options.OcrServiceBaseUrl.TrimEnd('/') + "/");

        var request = new OcrRequest(message.ExpenseId, message.TenantId, message.ReceiptBlobName);
        using var response = await httpClient.PostAsJsonAsync($"api/ocr/extract?code={Uri.EscapeDataString(options.OcrFunctionKey)}", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        return await response.Content.ReadFromJsonAsync<OcrResult>(cancellationToken) ?? throw new InvalidOperationException("OCR service returned an empty response.");
    }
}
