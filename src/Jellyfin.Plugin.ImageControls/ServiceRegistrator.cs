using Jellyfin.Plugin.ImageControls.Runtime;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;

namespace Jellyfin.Plugin.ImageControls;

public sealed class ServiceRegistrator : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        serviceCollection.AddSingleton<PlaybackBackendRegistry>();
        serviceCollection.AddSingleton<RuntimePatchState>();
        serviceCollection.AddHostedService<RuntimePatchHostedService>();
    }
}
