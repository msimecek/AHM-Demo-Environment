using ExpenseFlow.Shared;

namespace ExpenseFlow.Ocr;

public sealed record OcrOptions(
    string ReceiptContainerName,
    string StorageBlobServiceUri,
    int OcrDelayMs,
    double OcrFailureRate,
    bool ExternalOcrProviderHeartbeatEnabled,
    double ExternalOcrProviderHeartbeatSendProbability,
    string ExternalOcrProviderHealth,
    int ExternalOcrProviderHealthReportExpiresInMinutes,
    string HealthModelResourceId,
    string ExternalOcrProviderEntityName,
    string ExternalOcrProviderSignalName,
    string ExternalHealthReporterClientId)
{
    public static OcrOptions FromEnvironment()
    {
        return new OcrOptions(
            Configuration.Required("ExpenseFlow__ReceiptContainerName"),
            Configuration.Required("ExpenseFlow__StorageBlobServiceUri"),
            Configuration.OptionalInt("ExpenseFlow__OcrDelayMs", 500),
            Configuration.OptionalDouble("ExpenseFlow__OcrFailureRate", 0),
            Configuration.OptionalBool("ExpenseFlow__ExternalOcrProviderHeartbeatEnabled", false),
            Math.Clamp(Configuration.OptionalDouble("ExpenseFlow__ExternalOcrProviderHeartbeatSendProbability", 0.35), 0, 1),
            Configuration.Optional("ExpenseFlow__ExternalOcrProviderHealth", "Healthy"),
            Math.Clamp(Configuration.OptionalInt("ExpenseFlow__ExternalOcrProviderHealthReportExpiresInMinutes", 2), 1, 10080),
            Configuration.Optional("ExpenseFlow__HealthModelResourceId", string.Empty),
            Configuration.Optional("ExpenseFlow__ExternalOcrProviderEntityName", "external-ocr-provider"),
            Configuration.Optional("ExpenseFlow__ExternalOcrProviderSignalName", "external-ocr-provider-availability"),
            Configuration.Optional("ExpenseFlow__ExternalHealthReporterClientId", string.Empty));
    }
}
