using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using ExpenseFlow.Ocr;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        services.AddSingleton<TokenCredential, DefaultAzureCredential>();
        services.AddSingleton<HttpClient>();
        services.AddSingleton<ExternalHealthReporter>();
        services.AddSingleton(sp =>
        {
            var options = OcrOptions.FromEnvironment();
            return new BlobContainerClient(new Uri($"{options.StorageBlobServiceUri.TrimEnd('/')}/{options.ReceiptContainerName}"), sp.GetRequiredService<TokenCredential>());
        });
    })
    .Build();

await host.RunAsync();
