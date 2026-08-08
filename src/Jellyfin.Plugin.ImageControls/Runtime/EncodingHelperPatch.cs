using MediaBrowser.Controller.MediaEncoding;
using MediaBrowser.Model.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.ImageControls.Runtime;

internal static class EncodingHelperPatch
{
    private static PlaybackBackendRegistry? _registry;
    private static ILogger? _logger;
    private static bool _enabled;
    private static bool _enableSoftwareFfmpegBackend;
    private static bool _nvencOnly;
    private static bool _enableNvencFfmpegBackend;
    private static bool _allowNvencCopyBack;
    private static Action<string, long, string, string, bool>? _statusCallback;

    public static void Initialize(
        PlaybackBackendRegistry registry,
        ILogger logger,
        bool enabled,
        bool enableSoftwareFfmpegBackend,
        bool nvencOnly,
        bool enableNvencFfmpegBackend,
        bool allowNvencCopyBack,
        Action<string, long, string, string, bool>? statusCallback = null)
    {
        _registry = registry;
        _logger = logger;
        _enabled = enabled;
        _enableSoftwareFfmpegBackend = enableSoftwareFfmpegBackend;
        _nvencOnly = nvencOnly;
        _enableNvencFfmpegBackend = enableNvencFfmpegBackend;
        _allowNvencCopyBack = allowNvencCopyBack;
        _statusCallback = statusCallback;
    }

    private static void SetStatus(string clientId, long revision, string backend, string reason, bool ffmpegApplied)
    {
        _registry?.Set(clientId, revision, backend, reason, ffmpegApplied);
        _statusCallback?.Invoke(clientId, revision, backend, reason, ffmpegApplied);
    }

    public static void SoftwarePostfix(
        EncodingJobInfo state,
        string vidEncoder,
        ref (List<string> MainFilters, List<string> SubFilters, List<string> OverlayFilters) __result)
    {
        try
        {
            if (!_enabled || !_enableSoftwareFfmpegBackend)
            {
                return;
            }

            if (!AdjustmentParser.TryRead(state, out var values, out var clientId, out var revision))
            {
                return;
            }

            // Hard invariant: never turn video stream-copy into re-encoding.
            if (EncodingHelper.IsCopyCodec(state.OutputVideoCodec))
            {
                SetStatus(clientId, revision, "local", "Video codec is copy; FFmpeg image filter refused.", false);
                return;
            }

            // User deployment invariant: all server-side image filtering is tied to an existing
            // NVENC encode. Jellyfin may call this software filter-chain even when vidEncoder is
            // h264_nvenc/hevc_nvenc/av1_nvenc (for example when CUDA full filtering is unavailable).
            if (_nvencOnly
                && (string.IsNullOrWhiteSpace(vidEncoder)
                    || EncodingHelper.IsCopyCodec(vidEncoder)
                    || !vidEncoder.Contains("nvenc", StringComparison.OrdinalIgnoreCase)))
            {
                SetStatus(clientId, revision, "local", "NVENC-only mode: non-NVENC encoder refused.", false);
                return;
            }

            var filter = FfmpegFilterBuilder.Build(values);
            if (string.IsNullOrWhiteSpace(filter))
            {
                SetStatus(clientId, revision, "local", "Only client-side image controls are active.", false);
                return;
            }

            __result.MainFilters ??= new List<string>();
            __result.MainFilters.Add(filter);
            SetStatus(clientId, revision, "ffmpeg-software", "Existing software/copy-back video transcode; JFIC filter appended.", true);
            _logger?.LogDebug("JFIC appended software FFmpeg filter for client {ClientId}: {Filter}", clientId, filter);
        }
        catch (Exception ex)
        {
            _logger?.LogError(ex, "JFIC software FFmpeg postfix failed; playback will continue without server image filtering.");
        }
    }

    public static void NvidiaPostfix(
        EncodingJobInfo state,
        EncodingOptions options,
        string vidDecoder,
        string vidEncoder,
        ref (List<string> MainFilters, List<string> SubFilters, List<string> OverlayFilters) __result)
    {
        try
        {
            if (!_enabled || !_enableNvencFfmpegBackend || !_allowNvencCopyBack)
            {
                return;
            }

            if (!AdjustmentParser.TryRead(state, out var values, out var clientId, out var revision))
            {
                return;
            }

            // The preferred NVIDIA method can be entered with an NVDEC decoder and a software
            // encoder too. JFIC's NVIDIA backend is intentionally restricted to an actual NVENC
            // encoder because that is the deployment mode this project supports.
            if (EncodingHelper.IsCopyCodec(state.OutputVideoCodec)
                || EncodingHelper.IsCopyCodec(vidEncoder)
                || !vidEncoder.Contains("nvenc", StringComparison.OrdinalIgnoreCase))
            {
                SetStatus(clientId, revision, "local", "No active NVENC video encoder; server image filter refused.", false);
                return;
            }

            var currentSurfaceIsCuda = FfmpegFilterBuilder.NvidiaMainSurfaceIsCuda(__result.MainFilters, vidDecoder);
            var filters = FfmpegFilterBuilder.BuildNvencExistingTranscode(values, currentSurfaceIsCuda);
            if (filters.Count == 0)
            {
                SetStatus(clientId, revision, "local", "Only client-side image controls are active.", false);
                return;
            }

            __result.MainFilters ??= new List<string>();
            foreach (var filter in filters)
            {
                __result.MainFilters.Add(filter);
            }

            var mode = currentSurfaceIsCuda ? "NVENC/CUDA copy-back" : "NVENC with memory-frame filter";
            SetStatus(clientId, revision, "ffmpeg-nvenc", $"Existing {mode}; JFIC did not trigger transcoding.", true);
            _logger?.LogDebug(
                "JFIC appended NVIDIA filter plan for client {ClientId}; decoder={Decoder}, encoder={Encoder}, cudaSurface={CudaSurface}, filters={Filters}",
                clientId,
                vidDecoder,
                vidEncoder,
                currentSurfaceIsCuda,
                string.Join(',', filters));
        }
        catch (Exception ex)
        {
            _logger?.LogError(ex, "JFIC NVIDIA/NVENC postfix failed; playback will continue without server image filtering.");
        }
    }
}
