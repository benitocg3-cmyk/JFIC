using System.Globalization;
using Jellyfin.Plugin.ImageControls.Models;
using MediaBrowser.Controller.MediaEncoding;

namespace Jellyfin.Plugin.ImageControls.Runtime;

public static class AdjustmentParser
{
    public const string ClientIdKey = "jficClientId";
    public const string RevisionKey = "jficRevision";

    public static bool TryRead(EncodingJobInfo state, out ImageAdjustmentValues values, out string clientId, out long revision)
    {
        values = new ImageAdjustmentValues();
        clientId = string.Empty;
        revision = 0;
        var options = state.BaseRequest?.StreamOptions;
        if (options is null)
        {
            return false;
        }

        clientId = Get(options, ClientIdKey);
        _ = long.TryParse(Get(options, RevisionKey), NumberStyles.Integer, CultureInfo.InvariantCulture, out revision);
        values = new ImageAdjustmentValues
        {
            Brightness = Parse(options, "imageBrightness"),
            Contrast = Parse(options, "imageContrast"),
            Saturation = Parse(options, "imageSaturation"),
            Hue = Parse(options, "imageHue"),
            Gamma = Parse(options, "imageGamma"),
            Temperature = Parse(options, "imageTemperature")
        }.CloneAndClamp();

        return !values.IsNeutral;
    }

    private static int Parse(Dictionary<string, string> options, string key)
    {
        return options.TryGetValue(key, out var raw)
            && int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : 0;
    }

    private static string Get(Dictionary<string, string> options, string key)
        => options.TryGetValue(key, out var value) ? value : string.Empty;
}
