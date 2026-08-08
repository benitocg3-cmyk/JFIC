namespace Jellyfin.Plugin.ImageControls.Runtime;

public sealed class RuntimePatchState
{
    public bool PatchAttempted { get; internal set; }
    public bool PatchActive { get; internal set; }
    public string? LastError { get; internal set; }
    public DateTime? PatchedUtc { get; internal set; }
}
