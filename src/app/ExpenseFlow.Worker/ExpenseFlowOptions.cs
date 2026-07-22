using ExpenseFlow.Shared;

namespace ExpenseFlow.Worker;

public sealed record ExpenseFlowOptions(
    string ReceiptContainerName,
    string StorageBlobServiceUri,
    string CosmosEndpoint,
    string CosmosDatabaseName,
    string CosmosContainerName,
    string OcrServiceBaseUrl,
    string OcrFunctionKey,
    int ProcessingDelayMs)
{
    public static ExpenseFlowOptions FromEnvironment()
    {
        return new ExpenseFlowOptions(
            Configuration.Required("ExpenseFlow__ReceiptContainerName"),
            Configuration.Required("ExpenseFlow__StorageBlobServiceUri"),
            Configuration.Required("ExpenseFlow__CosmosEndpoint"),
            Configuration.Required("ExpenseFlow__CosmosDatabaseName"),
            Configuration.Required("ExpenseFlow__CosmosContainerName"),
            Configuration.Required("ExpenseFlow__OcrServiceBaseUrl"),
            Configuration.Required("ExpenseFlow__OcrFunctionKey"),
            Configuration.OptionalInt("ExpenseFlow__ProcessingDelayMs", 1000));
    }
}
