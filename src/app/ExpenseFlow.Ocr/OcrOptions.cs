using ExpenseFlow.Shared;

namespace ExpenseFlow.Ocr;

public sealed record OcrOptions(
    string ReceiptContainerName,
    string StorageBlobServiceUri,
    int OcrDelayMs,
    double OcrFailureRate)
{
    public static OcrOptions FromEnvironment()
    {
        return new OcrOptions(
            Configuration.Required("ExpenseFlow__ReceiptContainerName"),
            Configuration.Required("ExpenseFlow__StorageBlobServiceUri"),
            Configuration.OptionalInt("ExpenseFlow__OcrDelayMs", 500),
            Configuration.OptionalDouble("ExpenseFlow__OcrFailureRate", 0));
    }
}
