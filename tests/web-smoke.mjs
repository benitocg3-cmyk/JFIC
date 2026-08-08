import fs from 'node:fs';
const js = fs.readFileSync(new URL('../web/image-controls.js', import.meta.url), 'utf8');
for (const token of ['never changes playback capabilities', 'jficClientId', 'jficRevision', 'PlaybackStatus', 'mpv-set-image-controls', '.osdControls .buttons.focuscontainer-x', '.btnVideoOsdSettings', 'palette', 'insertBefore', "setProperty('order'", 'sepia', 'Math.pow(2', 'backend-status', 'mountLauncher', 'pointerDragging', 'jfic-value', 'source: \'keyboard\'']) {
  if (!js.includes(token)) throw new Error(`Missing expected token: ${token}`);
}
console.log('JFIC web smoke test OK');
