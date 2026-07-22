using ExpenseFlow.Shared;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace ExpenseFlow.Bff;

public sealed class Functions(SubmissionService submissions, ILogger<Functions> logger)
{
    [Function(nameof(SubmitSyntheticExpense))]
    public async Task<SubmitSyntheticExpenseOutput> SubmitSyntheticExpense(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "expenses/synthetic")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var message = await submissions.CreateSyntheticSubmissionAsync("control-panel", cancellationToken);
        logger.LogInformation("Submitted synthetic expense {ExpenseId} from control panel.", message.ExpenseId);

        var response = request.CreateResponse(System.Net.HttpStatusCode.Accepted);
        await response.WriteAsJsonAsync(new
        {
            message.ExpenseId,
            message.ReceiptBlobName,
            message.Vendor,
            message.Amount,
            message.Currency,
            message.Category,
            message.SubmittedAt
        }, cancellationToken);

        return new SubmitSyntheticExpenseOutput
        {
            Response = response,
            Message = message
        };
    }

    [Function(nameof(KeepAlive))]
    [ServiceBusOutput("%ExpensesQueueName%", Connection = "ServiceBusConnection")]
    public async Task<IReadOnlyList<ExpenseSubmittedMessage>> KeepAlive(
        [TimerTrigger("%KeepAliveSchedule%")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var options = ExpenseFlowOptions.FromEnvironment();
        if (!options.KeepAliveEnabled)
        {
            logger.LogInformation("Keep-alive timer fired but is disabled.");
            return [];
        }

        var messages = new List<ExpenseSubmittedMessage>(options.KeepAliveBatchSize);
        for (var index = 0; index < options.KeepAliveBatchSize; index++)
        {
            messages.Add(await submissions.CreateSyntheticSubmissionAsync("keep-alive", cancellationToken));
        }

        logger.LogInformation("Keep-alive submitted {Count} synthetic expense(s).", messages.Count);
        return messages;
    }
}

public sealed class SubmitSyntheticExpenseOutput
{
    [HttpResult]
    public HttpResponseData Response { get; init; } = default!;

    [ServiceBusOutput("%ExpensesQueueName%", Connection = "ServiceBusConnection")]
    public ExpenseSubmittedMessage Message { get; init; } = default!;
}
