namespace ExpenseFlow.Shared;

public static class SyntheticExpenseFactory
{
    private static readonly string[] Vendors = ["Contoso Travel", "Fabrikam Office", "Northwind Coffee", "Adventure Works Taxi", "Litware Hotel"];
    private static readonly string[] Categories = ["Travel", "Meals", "Office", "Transport", "Lodging"];

    public static (SyntheticReceipt Receipt, ExpenseSubmittedMessage Message) Create(string source)
    {
        var expenseId = $"exp-{DateTimeOffset.UtcNow:yyyyMMddHHmmssfff}-{Random.Shared.Next(1000, 9999)}";
        var vendor = Vendors[Random.Shared.Next(Vendors.Length)];
        var category = Categories[Random.Shared.Next(Categories.Length)];
        var amount = Math.Round((decimal)(Random.Shared.NextDouble() * 475.0 + 25.0), 2);
        var submittedAt = DateTimeOffset.UtcNow;
        var tenantId = "demo";
        var blobName = $"{submittedAt:yyyy/MM/dd}/{expenseId}.json";

        var receipt = new SyntheticReceipt(expenseId, tenantId, vendor, amount, "EUR", category, submittedAt, source);
        var message = new ExpenseSubmittedMessage(expenseId, tenantId, blobName, vendor, amount, "EUR", category, submittedAt, source);

        return (receipt, message);
    }
}
