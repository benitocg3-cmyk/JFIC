using System.Collections.Concurrent;
using Jellyfin.Plugin.ImageControls.Models;

namespace Jellyfin.Plugin.ImageControls.Runtime;

public sealed class PlaybackBackendRegistry
{
    private readonly ConcurrentDictionary<string, PlaybackBackendStatus> _items = new(StringComparer.OrdinalIgnoreCase);
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(45);

    public void Set(string clientId, long revision, string backend, string reason, bool ffmpegApplied)
    {
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return;
        }

        _items[clientId] = new PlaybackBackendStatus(clientId, revision, backend, reason, DateTime.UtcNow, ffmpegApplied);
    }

    public PlaybackBackendStatus Get(string clientId)
    {
        if (!string.IsNullOrWhiteSpace(clientId)
            && _items.TryGetValue(clientId, out var status)
            && DateTime.UtcNow - status.UpdatedUtc <= Ttl)
        {
            return status;
        }

        return new PlaybackBackendStatus(clientId ?? string.Empty, 0, "local", "No active FFmpeg image filter was confirmed.", DateTime.UtcNow, false);
    }
}
