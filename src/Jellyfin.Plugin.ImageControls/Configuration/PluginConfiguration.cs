using Jellyfin.Plugin.ImageControls.Models;
using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.ImageControls.Configuration;

public sealed class PluginConfiguration : BasePluginConfiguration
{
    public bool Enabled { get; set; } = true;

    public bool EnableRuntimeFfmpegPatch { get; set; } = true;

    // Software/copy-back chains: safe because they are reached only after Jellyfin has already
    // decided to re-encode video. JFIC never changes codec negotiation or Direct Play capabilities.
    public bool EnableSoftwareFfmpegBackend { get; set; } = true;

    // This deployment is intentionally NVIDIA-only. The software filter-chain hook remains
    // enabled because Jellyfin can route an NVENC encoder through GetSwVidFilterChain when
    // CUDA full acceleration is unavailable, but JFIC refuses non-NVENC video encoders.
    public bool NvencOnly { get; set; } = true;

    // Targeted backend for this deployment: existing NVIDIA/NVENC transcodes only.
    // CUDA has no eq_cuda equivalent for brightness/contrast/saturation/gamma/hue in the
    // Jellyfin 10.11.11 FFmpeg pipeline, so JFIC performs a controlled copy-back when needed:
    // CUDA -> hwdownload -> software eq/hue -> hwupload CUDA -> NVENC.
    public bool EnableNvencFfmpegBackend { get; set; } = true;

    // Keep this explicit so a future zero-copy implementation can be added without silently
    // changing the performance characteristics of an existing installation.
    public bool AllowNvencCopyBack { get; set; } = true;

    public List<ProfileEntry> Profiles { get; set; } = new();
}
