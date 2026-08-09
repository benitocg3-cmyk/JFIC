using System.Reflection;
using System.Runtime.Loader;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.ImageControls.Runtime;
/// <summary>
/// Installs the two server-side hooks without changing Jellyfin files or its
/// playback negotiation. The hooks only append a filter after Jellyfin has
/// already selected a video transcode; copy/direct-stream paths are refused by
/// EncodingHelperPatch.
/// </summary>
public sealed class RuntimePatchHostedService : IHostedService
{
    private readonly RuntimePatchState _state;
    private readonly PlaybackBackendRegistry _registry;
    private readonly ILogger<RuntimePatchHostedService> _logger;
    public RuntimePatchHostedService(
        RuntimePatchState state,
        PlaybackBackendRegistry registry,
        ILogger<RuntimePatchHostedService> logger)
    {
        _state = state;
        _registry = registry;
        _logger = logger;
    }
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _state.PatchAttempted = true;
        try
        {
            var configuration = Plugin.Instance?.Configuration;
            if (configuration is null || !configuration.Enabled || !configuration.EnableRuntimeFfmpegPatch)
            {
                _state.PatchActive = false;
                _state.LastError = null;
                _logger.LogInformation("JFIC runtime patch disabled by configuration.");
                return Task.CompletedTask;
            }

            var safeModeMarkerPath = ResolveSafeModeMarkerPath();
            if (File.Exists(safeModeMarkerPath))
            {
                _state.PatchActive = false;
                _state.LastError = null;
                _logger.LogWarning(
                    "JFIC safe mode is enabled; Harmony hooks were not installed. Marker: {SafeModeMarkerPath}",
                    safeModeMarkerPath);
                return Task.CompletedTask;
            }
            var patchAssembly = LoadDefaultContextPatchAssembly();
            var installMethod = patchAssembly
                .GetType(typeof(RuntimePatchHostedService).FullName!, throwOnError: true)!
                .GetMethod(nameof(InstallDefaultContext), BindingFlags.Public | BindingFlags.Static)
                ?? throw new MissingMethodException("JFIC default-context bootstrap method not found.");
            var statusCallback = new Action<string, long, string, string, bool>(_registry.Set);
            var installed = installMethod.Invoke(
                null,
                new object?[]
                {
                    configuration.Enabled,
                    configuration.EnableSoftwareFfmpegBackend,
                    configuration.NvencOnly,
                    configuration.EnableNvencFfmpegBackend,
                    configuration.AllowNvencCopyBack,
                    statusCallback
                });
            if (installed is not true)
            {
                throw new InvalidOperationException("JFIC default-context Harmony bootstrap returned false.");
            }
            _state.PatchActive = true;
            _state.LastError = null;
            _state.PatchedUtc = DateTime.UtcNow;
            _logger.LogInformation(
                "JFIC Harmony runtime patch active in AssemblyLoadContext.Default. Direct Stream/video-copy remains client-side.");
        }
        catch (Exception ex)
        {
            _state.PatchActive = false;
            _state.LastError = $"{ex.GetType().Name}: {ex.Message}";
            _logger.LogError(ex, "JFIC Harmony runtime patch could not be installed; playback continues without server image filtering.");
        }
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
    public static bool InstallDefaultContext(
        bool enabled,
        bool enableSoftwareFfmpegBackend,
        bool nvencOnly,
        bool enableNvencFfmpegBackend,
        bool allowNvencCopyBack,
        Action<string, long, string, string, bool>? statusCallback)
        => RuntimePatchBootstrap.Install(
            enabled,
            enableSoftwareFfmpegBackend,
            nvencOnly,
            enableNvencFfmpegBackend,
            allowNvencCopyBack,
            statusCallback);

    private static string ResolveSafeModeMarkerPath()
    {
        var overridePath = Environment.GetEnvironmentVariable("JFIC_SAFE_MODE_MARKER");
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            return overridePath;
        }

        if (OperatingSystem.IsWindows())
        {
            var commonApplicationData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            if (!string.IsNullOrWhiteSpace(commonApplicationData))
            {
                return Path.Combine(commonApplicationData, "jellyfin-image-controls", "disable-ffmpeg-patch");
            }
        }

        return "/var/lib/jellyfin-image-controls/disable-ffmpeg-patch";
    }

    private static Assembly LoadDefaultContextPatchAssembly()
    {
        var currentAssembly = typeof(RuntimePatchHostedService).Assembly;
        var pluginPath = currentAssembly.Location;
        if (string.IsNullOrWhiteSpace(pluginPath))
        {
            throw new InvalidOperationException("JFIC plugin assembly has no filesystem location.");
        }
        var pluginDirectory = Path.GetDirectoryName(pluginPath)!;
        var harmonyPath = Path.Combine(pluginDirectory, "0Harmony.dll");
        if (!File.Exists(harmonyPath))
        {
            throw new FileNotFoundException("JFIC Harmony dependency not found.", harmonyPath);
        }
        var harmony = AssemblyLoadContext.Default.Assemblies
            .FirstOrDefault(assembly => string.Equals(assembly.GetName().Name, "0Harmony", StringComparison.Ordinal));
        if (harmony is null)
        {
            _ = AssemblyLoadContext.Default.LoadFromAssemblyPath(harmonyPath);
        }
        var defaultPlugin = AssemblyLoadContext.Default.Assemblies
            .FirstOrDefault(assembly => string.Equals(assembly.Location, pluginPath, StringComparison.OrdinalIgnoreCase));
        return defaultPlugin ?? AssemblyLoadContext.Default.LoadFromAssemblyPath(pluginPath);
    }
}
