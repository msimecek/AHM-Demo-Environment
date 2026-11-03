using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using ExpenseFlow.Shared;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ExpenseFlow.Worker;

public sealed class Functions(BlobContainerClient receiptContainer, CosmosClient cosmosClient, OcrClient ocrClient, QueueClient poisonQueue, ILogger<Functions> logger)
{
    private const int MaxProcessingAttempts = 5;

    [Function(nameof(ProcessExpense))]
    // Keep retries active during poison-queue outages so the checkpoint cannot skip an expense.
    [FixedDelayRetry(-1, "00:00:10")]
    public async Task ProcessExpense(
        [EventHubTrigger("%ExpensesEventHubName%", Connection = "EventHubsConnection", ConsumerGroup = "%ExpensesConsumerGroup%", IsBatched = false)] ExpenseSubmittedMessage message,
        FunctionContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if ((context.RetryContext?.RetryCount ?? 0) >= MaxProcessingAttempts)
        {
            await poisonQueue.SendMessageAsync(
                BinaryData.FromObjectAsJson(message),
                timeToLive: TimeSpan.FromSeconds(-1),
                cancellationToken: cancellationToken);
            logger.LogError("Expense {ExpenseId} failed after {Attempts} processing attempts and was saved to poison queue {QueueName}.", message.ExpenseId, MaxProcessingAttempts, poisonQueue.Name);
            return;
        }

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
