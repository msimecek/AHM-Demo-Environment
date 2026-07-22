using ExpenseFlow.Shared;

namespace ExpenseFlow.Bff;

public sealed record ExpenseFlowOptions(
    string ReceiptContainerName,
    string StorageBlobServiceUri,
    bool KeepAliveEnabled,
    int KeepAliveBatchSize)
{
    public static ExpenseFlowOptions FromEnvironment()
    {
        return new ExpenseFlowOptions(
            Configuration.Required("ExpenseFlow__ReceiptContainerName"),
            Configuration.Required("ExpenseFlow__StorageBlobServiceUri"),
            Configuration.OptionalBool("ExpenseFlow__KeepAliveEnabled", true),
            Math.Max(1, Configuration.OptionalInt("ExpenseFlow__KeepAliveBatchSize", 1)));
    }
}
