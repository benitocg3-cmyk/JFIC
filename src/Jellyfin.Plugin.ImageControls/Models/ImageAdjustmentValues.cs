namespace Jellyfin.Plugin.ImageControls.Models;

public sealed class ImageAdjustmentValues
{
    public int Brightness { get; set; }
    public int Contrast { get; set; }
    public int Saturation { get; set; }
    public int Hue { get; set; }
    public int Gamma { get; set; }
    public int Temperature { get; set; }

    public bool IsNeutral => Brightness == 0 && Contrast == 0 && Saturation == 0 && Hue == 0 && Gamma == 0 && Temperature == 0;

    public ImageAdjustmentValues CloneAndClamp()
    {
        return new ImageAdjustmentValues
        {
            Brightness = Math.Clamp(Brightness, -100, 100),
            Contrast = Math.Clamp(Contrast, -100, 100),
            Saturation = Math.Clamp(Saturation, -100, 100),
            Hue = Math.Clamp(Hue, -180, 180),
            Gamma = Math.Clamp(Gamma, -100, 100),
            Temperature = Math.Clamp(Temperature, -100, 100)
        };
    }
}
