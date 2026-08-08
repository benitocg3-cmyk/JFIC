using Jellyfin.Plugin.ImageControls.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.ImageControls;

public sealed class Plugin : BasePlugin<PluginConfiguration>
{
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    public static Plugin? Instance { get; private set; }

    public override string Name => "Image Controls";

    public override Guid Id => Guid.Parse("2d0a5db1-fc4c-4ef4-9e4b-21fc31fd0b71");

    public override string Description => "Image controls for Jellyfin Web; Direct Stream stays client-side and existing video transcodes may use FFmpeg.";
}
