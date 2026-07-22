using System.Text.Json;
using Azure.Storage.Blobs;
using ExpenseFlow.Shared;

namespace ExpenseFlow.Bff;

public sealed class SubmissionService(BlobContainerClient receiptContainer)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<ExpenseSubmittedMessage> CreateSyntheticSubmissionAsync(string source, CancellationToken cancellationToken)
    {
        var (receipt, message) = SyntheticExpenseFactory.Create(source);
        var blobClient = receiptContainer.GetBlobClient(message.ReceiptBlobName);
        var content = BinaryData.FromString(JsonSerializer.Serialize(receipt, JsonOptions));

        await blobClient.UploadAsync(content, overwrite: true, cancellationToken);

        return message;
    }
}
