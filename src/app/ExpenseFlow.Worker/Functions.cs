using Azure.Storage.Blobs;
using ExpenseFlow.Shared;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ExpenseFlow.Worker;

public sealed class Functions(BlobContainerClient receiptContainer, CosmosClient cosmosClient, OcrClient ocrClient, ILogger<Functions> logger)
{
    [Function(nameof(ProcessExpense))]
    public async Task ProcessExpense(
        [ServiceBusTrigger("%ExpensesQueueName%", Connection = "ServiceBusConnection")] ExpenseSubmittedMessage message,
        CancellationToken cancellationToken)
    {
        var options = ExpenseFlowOptions.FromEnvironment();
        if (options.ProcessingDelayMs > 0)
        {
            await Task.Delay(options.ProcessingDelayMs, cancellationToken);
        }

        var blobClient = receiptContainer.GetBlobClient(message.ReceiptBlobName);
        if (!await blobClient.ExistsAsync(cancellationToken))
        {
            throw new InvalidOperationException($"Receipt blob '{message.ReceiptBlobName}' does not exist.");
        }

        var ocr = await ocrClient.ExtractAsync(message, cancellationToken);
        var record = new ExpenseRecord(
            message.ExpenseId,
            message.TenantId,
            ocr.Vendor,
            ocr.Amount,
            ocr.Currency,
            ocr.Category,
            "Processed",
            message.ReceiptBlobName,
            ocr.Confidence,
            message.SubmittedAt,
            DateTimeOffset.UtcNow);

        var container = cosmosClient.GetContainer(options.CosmosDatabaseName, options.CosmosContainerName);
        await container.UpsertItemAsync(record, new PartitionKey(record.TenantId), cancellationToken: cancellationToken);

        logger.LogInformation("Processed expense {ExpenseId}.", message.ExpenseId);
    }
}
