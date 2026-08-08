# Adaptateur Jellyfin Desktop / MPV

Le serveur Ubuntu ne peut pas modifier directement les propriétés d'un `libmpv` exécuté sur un autre PC. Il faut donc un petit adaptateur **dans Jellyfin Desktop**.

Le Web JFIC émet déjà :

```js
window.postMessage({
  source: 'jellyfin-image-controls',
  type: 'mpv-set-image-controls',
  values: { brightness, contrast, saturation, hue, gamma, temperature }
}, '*');
```

Jellyfin Desktop utilise actuellement Qt WebEngine et `libmpv`; le patch client doit convertir les cinq propriétés natives :

```text
brightness -> mpv property brightness
contrast   -> mpv property contrast
saturation -> mpv property saturation
hue        -> mpv property hue
gamma      -> mpv property gamma
```

La température n'a pas de propriété MPV équivalente simple et doit être traitée par shader ou laissée indisponible.

Ce module n'est volontairement **pas inclus dans l'installateur Ubuntu** : il doit être compilé/installé sur chaque poste Jellyfin Desktop. Cela garantit que désinstaller JFIC du serveur ne touche pas aux clients natifs.

Le projet serveur reste entièrement fonctionnel dans les navigateurs/Web sans cet adaptateur.


## Anti-double-filtrage

Le Web JFIC envoie désormais au pont MPV les **valeurs locales effectives** : si le serveur a confirmé que la révision courante est déjà appliquée par FFmpeg/NVENC, luminosité/contraste/saturation/teinte/gamma sont envoyés à zéro au pont MPV. La température, qui reste client-only, peut continuer à être traitée par un shader client.
