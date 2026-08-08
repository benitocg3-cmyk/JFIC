using Jellyfin.Plugin.ImageControls.Models;
using Jellyfin.Plugin.ImageControls.Runtime;
using Xunit;

namespace Jellyfin.Plugin.ImageControls.Tests;

public sealed class FfmpegFilterBuilderTests
{
    [Fact]
    public void NeutralValuesDoNotCreateServerFilter()
    {
        var result = FfmpegFilterBuilder.Build(new ImageAdjustmentValues());
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void TemperatureOnlyStaysClientSide()
    {
        var result = FfmpegFilterBuilder.Build(new ImageAdjustmentValues { Temperature = 25 });
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void EqContainsRequestedAdjustments()
    {
        var result = FfmpegFilterBuilder.Build(new ImageAdjustmentValues
        {
            Brightness = 10,
            Contrast = 10,
            Saturation = 15,
            Gamma = 10
        });

        Assert.Contains("brightness=0.05", result, StringComparison.Ordinal);
        Assert.Contains("contrast=1.1", result, StringComparison.Ordinal);
        Assert.Contains("saturation=1.15", result, StringComparison.Ordinal);
        Assert.Contains("gamma=", result, StringComparison.Ordinal);
    }

    [Fact]
    public void HueIsAppendedWhenRequested()
    {
        var result = FfmpegFilterBuilder.Build(new ImageAdjustmentValues { Hue = 15 });
        Assert.Contains("hue=h=15", result, StringComparison.Ordinal);
    }

    [Fact]
    public void NvencCudaSurfaceUsesControlledCopyBack()
    {
        var result = FfmpegFilterBuilder.BuildNvencExistingTranscode(
            new ImageAdjustmentValues { Brightness = 10 },
            currentSurfaceIsCuda: true);

        Assert.Equal("hwdownload", result[0]);
        Assert.Equal("format=yuv420p", result[1]);
        Assert.Contains("eq=", result[2], StringComparison.Ordinal);
        Assert.Equal("hwupload=derive_device=cuda", result[3]);
    }

    [Fact]
    public void NvencMemorySurfaceDoesNotDownloadOrUpload()
    {
        var result = FfmpegFilterBuilder.BuildNvencExistingTranscode(
            new ImageAdjustmentValues { Contrast = 20 },
            currentSurfaceIsCuda: false);

        Assert.Single(result);
        Assert.Contains("eq=", result[0], StringComparison.Ordinal);
    }

    [Fact]
    public void NvidiaSurfaceTrackingRecognizesCudaDecoder()
    {
        Assert.True(FfmpegFilterBuilder.NvidiaMainSurfaceIsCuda(
            new[] { "scale_cuda=format=yuv420p" },
            " -hwaccel cuda -hwaccel_output_format cuda"));
    }

    [Fact]
    public void NvidiaSurfaceTrackingRecognizesFinalDownload()
    {
        Assert.False(FfmpegFilterBuilder.NvidiaMainSurfaceIsCuda(
            new[] { "scale_cuda=format=yuv420p", "hwdownload", "format=yuv420p" },
            " -hwaccel cuda -hwaccel_output_format cuda"));
    }

    [Fact]
    public void NvidiaSurfaceTrackingRecognizesCudaUploadAndTonemap()
    {
        Assert.True(FfmpegFilterBuilder.NvidiaMainSurfaceIsCuda(
            new[] { "format=yuv420p", "hwupload=derive_device=cuda", "tonemap_cuda=format=yuv420p" },
            string.Empty));
    }

    [Fact]
    public void NvidiaSurfaceTrackingLeavesSoftwareFramesInMemory()
    {
        Assert.False(FfmpegFilterBuilder.NvidiaMainSurfaceIsCuda(
            new[] { "format=yuv420p" },
            string.Empty));
    }
}
