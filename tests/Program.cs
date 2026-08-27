using RuntimeInstaller;

var input = new RuntimeInput(
    "desktop-x64", "dotnet-desktop", TargetArchitecture.X64,
    "https://dotnetcli.blob.core.windows.net/dotnet/Runtime/example.exe",
    new string('a', 64), "CN=Microsoft Corporation");

var frameworkOld = new RuntimeInput(
    "framework-48", "dotnet-framework", TargetArchitecture.X64,
    "https://download.microsoft.com/example.exe", new string('b', 64),
    "CN=Microsoft Corporation", 48);
var frameworkNew = frameworkOld with { Id = "framework-481", Sha256 = new string('c', 64), InPlaceRank = 481 };

var plan = InstallerPlan.Resolve(
    new[] { input, frameworkOld, frameworkNew },
    new InstallSelection(TargetArchitecture.X64, new HashSet<string> { "dotnet-desktop", "dotnet-framework" }));

if (plan.Count != 2 || plan.Single(item => item.Feature == "dotnet-framework").Id != "framework-481")
{
    throw new Exception("The highest compatible .NET Framework input was not selected.");
}

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Resolve(
        new[] { input },
        new InstallSelection(TargetArchitecture.Arm64, new HashSet<string> { "directx-legacy" })),
    "no reviewed ARM64 input");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Validate(input with { Url = "https://example.invalid/runtime.exe" }),
    "approved Microsoft host");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Resolve(
        new[] { input },
        new InstallSelection(TargetArchitecture.X64, new HashSet<string>())),
    "At least one feature");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Resolve(
        new[] { input },
        new InstallSelection(TargetArchitecture.X64, new HashSet<string> { "unknown-runtime" })),
    "Unknown feature: unknown-runtime");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Resolve(
        new[] { input },
        new InstallSelection(TargetArchitecture.Arm64, new HashSet<string> { "dotnet-desktop" })),
    "No reviewed dotnet-desktop input is available for Arm64");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Validate(input with { Sha256 = "not-a-sha256-digest" }),
    "invalid SHA-256 digest");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Validate(input with { Url = "http://download.microsoft.com/runtime.exe" }),
    "does not use HTTPS");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Validate(input with { SignerSubject = "CN=Contoso Software" }),
    "unexpected signer");

AssertThrows<InvalidOperationException>(
    () => InstallerPlan.Resolve(
        new[]
        {
            frameworkNew,
            frameworkNew with { Id = "framework-481-duplicate", Sha256 = new string('d', 64) },
        },
        new InstallSelection(TargetArchitecture.X64, new HashSet<string> { "dotnet-framework" })),
    "resolve to one highest-ranked input");

Console.WriteLine("RuntimeInstaller tests passed.");

static void AssertThrows<TException>(Action action, string? expectedMessageFragment = null)
    where TException : Exception
{
    try
    {
        action();
    }
    catch (Exception exception)
    {
        if (exception.GetType() != typeof(TException))
        {
            throw new Exception($"Expected exactly {typeof(TException).Name}, but got {exception.GetType().Name}.");
        }

        if (expectedMessageFragment is not null &&
            !exception.Message.Contains(expectedMessageFragment, StringComparison.Ordinal))
        {
            throw new Exception(
                $"Expected {typeof(TException).Name} message to contain '{expectedMessageFragment}', " +
                $"but it was '{exception.Message}'.");
        }

        return;
    }

    throw new Exception($"Expected {typeof(TException).Name} to be thrown.");
}
