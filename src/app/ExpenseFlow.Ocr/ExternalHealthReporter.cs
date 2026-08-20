using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Logging;

namespace ExpenseFlow.Ocr;

public sealed class ExternalHealthReporter(HttpClient httpClient, ILogger<ExternalHealthReporter> logger)
{
    private static readonly TokenRequestContext ArmTokenRequest = new(["https://management.azure.com/.default"]);

    public async Task ReportAsync(OcrOptions options, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.HealthModelResourceId))
        {
            throw new InvalidOperationException("Missing required configuration value 'ExpenseFlow__HealthModelResourceId'.");
        }

        if (string.IsNullOrWhiteSpace(options.ExternalHealthReporterClientId))
        {
            throw new InvalidOperationException("Missing required configuration value 'ExpenseFlow__ExternalHealthReporterClientId'.");
        }

        var healthState = NormalizeHealthState(options.ExternalOcrProviderHealth);
        var credential = new ManagedIdentityCredential(ManagedIdentityId.FromUserAssignedClientId(options.ExternalHealthReporterClientId));
        var token = await credential.GetTokenAsync(ArmTokenRequest, cancellationToken);
        var requestUri = BuildIngestUri(options);
        using var request = new HttpRequestMessage(HttpMethod.Post, requestUri)
        {
            Content = new StringContent(JsonSerializer.Serialize(new
            {
                signalName = options.ExternalOcrProviderSignalName,
                healthState,
                expiresInMinutes = options.ExternalOcrProviderHealthReportExpiresInMinutes,
                additionalContext = "External OCR provider heartbeat reported by the OCR Function demo adapter."
            }), Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new InvalidOperationException($"External OCR provider health report failed with HTTP {(int)response.StatusCode}: {body}");
        }

        logger.LogInformation(
            "Reported external OCR provider health {HealthState} for signal {SignalName}.",
            healthState,
            options.ExternalOcrProviderSignalName);
    }

    private static Uri BuildIngestUri(OcrOptions options)
    {
        var healthModelResourceId = options.HealthModelResourceId.TrimEnd('/');
        var entityName = Uri.EscapeDataString(options.ExternalOcrProviderEntityName);
        return new Uri($"https://management.azure.com{healthModelResourceId}/entities/{entityName}/ingestHealthReport?api-version=2026-05-01-preview");
    }

    private static string NormalizeHealthState(string healthState)
    {
        return healthState.Trim().ToLowerInvariant() switch
        {
            "healthy" => "Healthy",
            "degraded" => "Degraded",
            "unhealthy" => "Unhealthy",
            "unknown" => "Unknown",
            _ => throw new InvalidOperationException($"Unsupported external OCR provider health state '{healthState}'. Use Healthy, Degraded, Unhealthy, or Unknown.")
        };
    }
}
