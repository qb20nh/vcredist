using System.Security.Cryptography;

namespace RuntimeInstaller;

public enum TargetArchitecture
{
    X86,
    X64,
    Arm64,
}

public sealed record RuntimeInput(
    string Id,
    string Feature,
    TargetArchitecture Architecture,
    string Url,
    string Sha256,
    string SignerSubject,
    int InPlaceRank = 0);

public sealed record InstallSelection(TargetArchitecture Architecture, IReadOnlySet<string> Features);

public static class InstallerPlan
{
    private const string ApprovedMicrosoftOrganization = "O=Microsoft Corporation";

    private static readonly HashSet<string> ValidFeatures = new(StringComparer.Ordinal)
    {
        "vc-redist-v14",
        "dotnet-desktop",
        "dotnet-aspnet",
        "dotnet-framework",
        "dotnet-framework-35",
        "directx-legacy",
    };

    private static readonly HashSet<string> ApprovedSourceHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "download.microsoft.com",
        "download.windowsupdate.com",
        "download.visualstudio.microsoft.com",
        "dotnetcli.blob.core.windows.net",
        "builds.dotnet.microsoft.com",
    };

    public static IReadOnlyList<RuntimeInput> Resolve(
        IEnumerable<RuntimeInput> available,
        InstallSelection selection)
    {
        if (selection.Features.Count == 0)
        {
            throw new InvalidOperationException("At least one feature must be selected.");
        }

        foreach (var feature in selection.Features)
        {
            if (!ValidFeatures.Contains(feature))
            {
                throw new InvalidOperationException($"Unknown feature: {feature}.");
            }
        }

        if (selection.Architecture == TargetArchitecture.Arm64 && selection.Features.Contains("directx-legacy"))
        {
            throw new InvalidOperationException("The legacy DirectX June 2010 package has no reviewed ARM64 input.");
        }

        var candidates = available
            .Where(input => selection.Features.Contains(input.Feature))
            .Where(input => input.Architecture == selection.Architecture)
            .Select(Validate)
            .ToList();

        foreach (var feature in selection.Features)
        {
            if (!candidates.Any(input => input.Feature == feature))
            {
                throw new InvalidOperationException($"No reviewed {feature} input is available for {selection.Architecture}.");
            }
        }

        var framework = candidates.Where(input => input.Feature == "dotnet-framework").ToList();
        if (framework.Count > 1)
        {
            var maximumRank = framework.Max(input => input.InPlaceRank);
            candidates.RemoveAll(input => input.Feature == "dotnet-framework" && input.InPlaceRank != maximumRank);
            if (candidates.Count(input => input.Feature == "dotnet-framework") != 1)
            {
                throw new InvalidOperationException("A .NET Framework 4.x selection must resolve to one highest-ranked input.");
            }
        }

        return candidates.OrderBy(input => input.Feature, StringComparer.Ordinal)
            .ThenBy(input => input.Id, StringComparer.Ordinal)
            .ToList();
    }

    public static RuntimeInput Validate(RuntimeInput input)
    {
        if (!Uri.TryCreate(input.Url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException($"{input.Id} does not use HTTPS.");
        }

        if (!ApprovedSourceHosts.Contains(uri.Host))
        {
            throw new InvalidOperationException($"{input.Id} does not use an approved Microsoft host.");
        }

        if (input.Sha256.Length != 64 || !input.Sha256.All(Uri.IsHexDigit))
        {
            throw new InvalidOperationException($"{input.Id} has an invalid SHA-256 digest.");
        }
        if (!input.SignerSubject.Split(',').Select(attribute => attribute.Trim())
            .Contains(ApprovedMicrosoftOrganization, StringComparer.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"{input.Id} has an unexpected signer.");
        }

        return input;
    }

    public static string Fingerprint(IEnumerable<RuntimeInput> inputs)
    {
        var material = string.Join("\n", inputs.OrderBy(input => input.Id, StringComparer.Ordinal)
            .Select(input => $"{input.Id}:{input.Sha256}"));
        return Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(material))).ToLowerInvariant();
    }
}
