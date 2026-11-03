using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using ExpenseFlow.Shared;
using ExpenseFlow.Worker;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        services.AddHttpClient<OcrClient>();
        services.AddSingleton<TokenCredential, DefaultAzureCredential>();
        services.AddSingleton(sp =>
        {
            var serviceUri = Configuration.Required("ExpenseFlow__StorageQueueServiceUri");
            var queueName = Configuration.Required("ExpenseFlow__PoisonQueueName");
            return new QueueClient(new Uri($"{serviceUri.TrimEnd('/')}/{queueName}"), sp.GetRequiredService<TokenCredential>(), new QueueClientOptions
            {
                MessageEncoding = QueueMessageEncoding.Base64
            });
        });
        services.AddSingleton(sp =>
        {
            var options = ExpenseFlowOptions.FromEnvironment();
            return new BlobContainerClient(new Uri($"{options.StorageBlobServiceUri.TrimEnd('/')}/{options.ReceiptContainerName}"), sp.GetRequiredService<TokenCredential>());
        });
        services.AddSingleton(sp =>
        {
            var options = ExpenseFlowOptions.FromEnvironment();
            return new CosmosClient(options.CosmosEndpoint, sp.GetRequiredService<TokenCredential>(), new CosmosClientOptions
            {
                SerializerOptions = new CosmosSerializationOptions
                {
                    PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
                }
            });
        });
    })
    .Build();

await host.RunAsync();
