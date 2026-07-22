namespace ExpenseFlow.Shared;

public sealed record SyntheticReceipt(
    string ExpenseId,
    string TenantId,
    string Vendor,
    decimal Amount,
    string Currency,
    string Category,
    DateTimeOffset SubmittedAt,
    string Source);

public sealed record ExpenseSubmittedMessage(
    string ExpenseId,
    string TenantId,
    string ReceiptBlobName,
    string Vendor,
    decimal Amount,
    string Currency,
    string Category,
    DateTimeOffset SubmittedAt,
    string Source);

public sealed record OcrRequest(
    string ExpenseId,
    string TenantId,
    string ReceiptBlobName);

public sealed record OcrResult(
    string ExpenseId,
    string Vendor,
    decimal Amount,
    string Currency,
    string Category,
    double Confidence,
    DateTimeOffset ProcessedAt);

public sealed record ExpenseRecord(
    string Id,
    string TenantId,
    string Vendor,
    decimal Amount,
    string Currency,
    string Category,
    string Status,
    string ReceiptBlobName,
    double OcrConfidence,
    DateTimeOffset SubmittedAt,
    DateTimeOffset ProcessedAt);
