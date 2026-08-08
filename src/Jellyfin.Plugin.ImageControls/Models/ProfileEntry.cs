namespace Jellyfin.Plugin.ImageControls.Models;

public sealed class ProfileEntry
{
    public string UserId { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
    public string Scope { get; set; } = "device";
    public DateTime UpdatedUtc { get; set; } = DateTime.UtcNow;
    public ImageAdjustmentValues Values { get; set; } = new();
}

public sealed class ProfileRequest
{
    public string UserId { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
    public string Scope { get; set; } = "device";
    public ImageAdjustmentValues Values { get; set; } = new();
}
