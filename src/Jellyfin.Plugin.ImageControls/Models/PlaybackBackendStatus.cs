namespace Jellyfin.Plugin.ImageControls.Models;

public sealed record PlaybackBackendStatus(
    string ClientId,
    long Revision,
    string Backend,
    string Reason,
    DateTime UpdatedUtc,
    bool FfmpegApplied);
