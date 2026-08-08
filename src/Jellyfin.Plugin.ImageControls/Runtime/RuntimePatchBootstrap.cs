using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.MediaEncoding;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.ImageControls.Runtime;

/// <summary>
/// Runs from a copy of the plugin assembly loaded in AssemblyLoadContext.Default.
/// Jellyfin loads normal plugins in a collectible context; Harmony's generated
/// non-collectible wrappers cannot reference patch methods from that context.
/// </summary>
public static class RuntimePatchBootstrap
{
    private static int _installed;

    public static bool Install(
        bool enabled,
        bool enableSoftwareFfmpegBackend,
        bool nvencOnly,
        bool enableNvencFfmpegBackend,
        bool allowNvencCopyBack,
        Action<string, long, string, string, bool>? statusCallback)
    {
        if (Interlocked.CompareExchange(ref _installed, 1, 0) != 0)
        {
            return true;
        }

        try
        {
            EncodingHelperPatch.Initialize(
                new PlaybackBackendRegistry(),
                NullLogger.Instance,
                enabled,
                enableSoftwareFfmpegBackend,
                nvencOnly,
                enableNvencFfmpegBackend,
                allowNvencCopyBack,
                statusCallback);

            var software = FindMethod(
                "GetSwVidFilterChain",
                typeof(EncodingJobInfo),
                typeof(MediaBrowser.Model.Configuration.EncodingOptions),
                typeof(string));
            var nvidia = FindMethod(
                "GetNvidiaVidFiltersPrefered",
                typeof(EncodingJobInfo),
                typeof(MediaBrowser.Model.Configuration.EncodingOptions),
                typeof(string),
                typeof(string));

            if (software is null || nvidia is null)
            {
                throw new MissingMethodException(
                    $"Jellyfin EncodingHelper hooks not found (software={software is not null}, nvidia={nvidia is not null}).");
            }

            var harmony = new Harmony("jellyfin.plugin.imagecontrols");
            harmony.Patch(
                software,
                postfix: new HarmonyMethod(typeof(EncodingHelperPatch), nameof(EncodingHelperPatch.SoftwarePostfix)));
            harmony.Patch(
                nvidia,
                postfix: new HarmonyMethod(typeof(EncodingHelperPatch), nameof(EncodingHelperPatch.NvidiaPostfix)));
            return true;
        }
        catch
        {
            Interlocked.Exchange(ref _installed, 0);
            throw;
        }
    }

    private static MethodInfo? FindMethod(string name, params Type[] parameterTypes)
        => typeof(EncodingHelper).GetMethod(
            name,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            binder: null,
            types: parameterTypes,
            modifiers: null);
}
