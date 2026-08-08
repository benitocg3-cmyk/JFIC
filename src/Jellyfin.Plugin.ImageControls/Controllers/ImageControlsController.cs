using Jellyfin.Plugin.ImageControls.Models;
using Jellyfin.Plugin.ImageControls.Runtime;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.ImageControls.Controllers;

[ApiController]
[Authorize]
[Route("ImageControls")]
public sealed class ImageControlsController : ControllerBase
{
    private static readonly object ProfileLock = new();
    private readonly PlaybackBackendRegistry _registry;
    private readonly RuntimePatchState _patchState;

    public ImageControlsController(PlaybackBackendRegistry registry, RuntimePatchState patchState)
    {
        _registry = registry;
        _patchState = patchState;
    }

    [HttpGet("Capabilities")]
    [AllowAnonymous]
    public IActionResult Capabilities() => Ok(new
    {
        projectVersion = "1.0.0-beta2",
        targetJellyfin = "10.11.11",
        invariant = "never-force-video-transcode",
        runtimePatchAttempted = _patchState.PatchAttempted,
        runtimePatchActive = _patchState.PatchActive,
        runtimePatchError = _patchState.LastError,
            backends = new
            {
                web = true,
                ffmpegSoftwareChain = _patchState.PatchActive,
                ffmpegNvencExistingTranscode = _patchState.PatchActive,
                ffmpegNvencMode = _patchState.PatchActive ? "existing-transcode-only" : "unavailable",
                nvencOnly = Plugin.Instance?.Configuration.NvencOnly ?? true,
            ffmpegCanTriggerTranscode = false,
            temperatureServerSide = false,
            mpv = "requires-client-adapter"
        }
    });

    [HttpGet("PlaybackStatus")]
    public ActionResult<PlaybackBackendStatus> PlaybackStatus([FromQuery] string clientId)
        => Ok(_registry.Get(clientId));

    [HttpGet("Profile")]
    public ActionResult<ProfileEntry> GetProfile([FromQuery] string userId, [FromQuery] string clientId)
    {
        var plugin = Plugin.Instance;
        if (plugin is null || string.IsNullOrWhiteSpace(userId))
        {
            return BadRequest();
        }

        lock (ProfileLock)
        {
            var profiles = plugin.Configuration.Profiles;
            var result = profiles.LastOrDefault(p => Same(p.UserId, userId) && Same(p.ClientId, clientId) && Same(p.Scope, "device"))
                         ?? profiles.LastOrDefault(p => Same(p.UserId, userId) && Same(p.Scope, "user"))
                         ?? new ProfileEntry { UserId = userId, ClientId = clientId };
            return Ok(result);
        }
    }

    [HttpPut("Profile")]
    public ActionResult<ProfileEntry> PutProfile([FromBody] ProfileRequest request)
    {
        var plugin = Plugin.Instance;
        if (plugin is null || string.IsNullOrWhiteSpace(request.UserId))
        {
            return BadRequest();
        }

        var scope = Same(request.Scope, "user") ? "user" : "device";
        var clientId = scope == "user" ? string.Empty : request.ClientId ?? string.Empty;
        var values = (request.Values ?? new ImageAdjustmentValues()).CloneAndClamp();

        lock (ProfileLock)
        {
            var configuration = plugin.Configuration;
            var profile = configuration.Profiles.FirstOrDefault(p => Same(p.UserId, request.UserId) && Same(p.ClientId, clientId) && Same(p.Scope, scope));
            if (profile is null)
            {
                profile = new ProfileEntry { UserId = request.UserId, ClientId = clientId, Scope = scope };
                configuration.Profiles.Add(profile);
            }

            profile.Values = values;
            profile.UpdatedUtc = DateTime.UtcNow;
            plugin.UpdateConfiguration(configuration);
            return Ok(profile);
        }
    }

    private static bool Same(string? left, string? right)
        => string.Equals(left ?? string.Empty, right ?? string.Empty, StringComparison.OrdinalIgnoreCase);
}
