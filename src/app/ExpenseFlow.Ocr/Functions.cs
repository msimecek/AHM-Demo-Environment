using Azure.Storage.Blobs;
using ExpenseFlow.Shared;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace ExpenseFlow.Ocr;

public sealed class Functions(BlobContainerClient receiptContainer, ILogger<Functions> logger)
{
    [Function(nameof(ExtractReceipt))]
    public async Task<HttpResponseData> ExtractReceipt(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "ocr/extract")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var ocrRequest = await request.ReadFromJsonAsync<OcrRequest>(cancellationToken);
        if (ocrRequest is null)
        {
            var badRequest = request.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await badRequest.WriteStringAsync("Request body is required.", cancellationToken);
            return badRequest;
        }

        var options = OcrOptions.FromEnvironment();
        if (options.OcrDelayMs > 0)
        {
            await Task.Delay(options.OcrDelayMs, cancellationToken);
        }

        if (options.OcrFailureRate > 0 && Random.Shared.NextDouble() < options.OcrFailureRate)
        {
            logger.LogWarning("Simulated OCR failure for expense {ExpenseId}.", ocrRequest.ExpenseId);
            var failed = request.CreateResponse(System.Net.HttpStatusCode.ServiceUnavailable);
            await failed.WriteStringAsync("Simulated OCR failure.", cancellationToken);
            return failed;
        }

        var blobClient = receiptContainer.GetBlobClient(ocrRequest.ReceiptBlobName);
        var receipt = await blobClient.DownloadContentAsync(cancellationToken);
        var syntheticReceipt = receipt.Value.Content.ToObjectFromJson<SyntheticReceipt>() ?? throw new InvalidOperationException("Receipt blob could not be deserialized.");
        var result = new OcrResult(
            ocrRequest.ExpenseId,
            syntheticReceipt.Vendor,
            syntheticReceipt.Amount,
            syntheticReceipt.Currency,
            syntheticReceipt.Category,
            Math.Round(0.92 + Random.Shared.NextDouble() * 0.07, 2),
            DateTimeOffset.UtcNow);

        var response = request.CreateResponse(System.Net.HttpStatusCode.OK);
        await response.WriteAsJsonAsync(result, cancellationToken);
        return response;
    }
}
