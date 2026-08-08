using System.Globalization;
using Jellyfin.Plugin.ImageControls.Models;

namespace Jellyfin.Plugin.ImageControls.Runtime;

public static class FfmpegFilterBuilder
{
    public static bool HasServerAdjustments(ImageAdjustmentValues input)
    {
        var v = input.CloneAndClamp();
        return v.Brightness != 0
            || v.Contrast != 0
            || v.Saturation != 0
            || v.Hue != 0
            || v.Gamma != 0;
    }

    /// <summary>
    /// Builds the software FFmpeg part. Temperature intentionally remains client-side.
    /// </summary>
    public static string Build(ImageAdjustmentValues input)
    {
        var v = input.CloneAndClamp();
        if (!HasServerAdjustments(v))
        {
            return string.Empty;
        }

        var brightness = v.Brightness / 200.0; // -0.5 .. +0.5; conservative FFmpeg eq range.
        var contrast = Math.Clamp(1.0 + v.Contrast / 100.0, 0.0, 2.0);
        var saturation = Math.Clamp(1.0 + v.Saturation / 100.0, 0.0, 2.0);
        var gamma = Math.Clamp(Math.Pow(2.0, v.Gamma / 100.0), 0.5, 2.0);

        var parts = new List<string>
        {
            string.Format(
                CultureInfo.InvariantCulture,
                "eq=brightness={0:0.####}:contrast={1:0.####}:saturation={2:0.####}:gamma={3:0.####}",
                brightness,
                contrast,
                saturation,
                gamma)
        };

        if (v.Hue != 0)
        {
            parts.Add(string.Format(CultureInfo.InvariantCulture, "hue=h={0}", v.Hue));
        }

        return string.Join(',', parts);
    }

    /// <summary>
    /// Appends JFIC to an already-existing NVIDIA pipeline. If the current main-video surface
    /// is CUDA, use the same yuv420p copy-back convention already used by Jellyfin 10.11.11's
    /// NVIDIA filter chain, then upload to CUDA again so overlay_cuda/NVENC can continue.
    /// </summary>
    public static IReadOnlyList<string> BuildNvencExistingTranscode(ImageAdjustmentValues input, bool currentSurfaceIsCuda)
    {
        var software = Build(input);
        if (string.IsNullOrWhiteSpace(software))
        {
            return Array.Empty<string>();
        }

        if (!currentSurfaceIsCuda)
        {
            return new[] { software };
        }

        return new[]
        {
            "hwdownload",
            "format=yuv420p",
            software,
            "hwupload=derive_device=cuda"
        };
    }

    /// <summary>
    /// Best-effort surface tracking for the exact Jellyfin 10.11.11 NVIDIA filter-list model.
    /// The result is intentionally conservative: a final hwdownload means memory, while CUDA
    /// filters/hwupload mean a CUDA surface. An NVDEC input with no transfer filters is CUDA.
    /// </summary>
    public static bool NvidiaMainSurfaceIsCuda(IEnumerable<string>? filters, string? vidDecoder)
    {
        var isCuda = !string.IsNullOrWhiteSpace(vidDecoder)
            && vidDecoder.Contains("cuda", StringComparison.OrdinalIgnoreCase);

        if (filters is null)
        {
            return isCuda;
        }

        foreach (var raw in filters)
        {
            var filter = raw ?? string.Empty;
            if (filter.Contains("hwdownload", StringComparison.OrdinalIgnoreCase))
            {
                isCuda = false;
            }

            if (filter.Contains("hwupload", StringComparison.OrdinalIgnoreCase)
                && filter.Contains("cuda", StringComparison.OrdinalIgnoreCase))
            {
                isCuda = true;
            }

            if (filter.Contains("_cuda", StringComparison.OrdinalIgnoreCase)
                || filter.StartsWith("scale_cuda", StringComparison.OrdinalIgnoreCase)
                || filter.StartsWith("tonemap_cuda", StringComparison.OrdinalIgnoreCase)
                || filter.StartsWith("overlay_cuda", StringComparison.OrdinalIgnoreCase))
            {
                isCuda = true;
            }
        }

        return isCuda;
    }
}
