namespace ExpenseFlow.Shared;

public static class Configuration
{
    public static string Required(string name)
    {
        return Environment.GetEnvironmentVariable(name) ?? throw new InvalidOperationException($"Missing required configuration value '{name}'.");
    }

    public static string Optional(string name, string fallback)
    {
        return Environment.GetEnvironmentVariable(name) ?? fallback;
    }

    public static int OptionalInt(string name, int fallback)
    {
        return int.TryParse(Environment.GetEnvironmentVariable(name), out var value) ? value : fallback;
    }

    public static bool OptionalBool(string name, bool fallback)
    {
        return bool.TryParse(Environment.GetEnvironmentVariable(name), out var value) ? value : fallback;
    }

    public static double OptionalDouble(string name, double fallback)
    {
        return double.TryParse(Environment.GetEnvironmentVariable(name), out var value) ? value : fallback;
    }
}
