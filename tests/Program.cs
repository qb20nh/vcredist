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

try
{
    InstallerPlan.Resolve(
        new[] { input },
        new InstallSelection(TargetArchitecture.Arm64, new HashSet<string> { "directx-legacy" }));
    throw new Exception("ARM64 DirectX selection was not rejected.");
}
catch (InvalidOperationException)
{
}

try
{
    InstallerPlan.Validate(input with { Url = "https://example.invalid/runtime.exe" });
    throw new Exception("Unapproved source host was not rejected.");
}
catch (InvalidOperationException)
{
}

Console.WriteLine("RuntimeInstaller tests passed.");
