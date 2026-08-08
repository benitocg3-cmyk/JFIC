/* Jellyfin Image Controls 1.0.0-beta2
 * Invariant: this code never changes playback capabilities and never asks Jellyfin to transcode.
 * It only decorates already-selected video URLs and applies post-decode client filters.
 */
(() => {
    'use strict';
    if (window.__JFIC_LOADED__) return;
    window.__JFIC_LOADED__ = true;

    const VERSION = '1.0.0-beta2';
    // v3 intentionally starts neutral after the GPU-safe client filter change;
    // old profiles may contain values that were applied through the unstable SVG path.
    const PROFILE_KEY = 'jfic.profile.v3';
    const CLIENT_KEY = 'jfic.client-id.v1';
    const REVISION_KEY = 'jfic.revision.v1';
    const DEFAULTS = { brightness: 0, contrast: 0, saturation: 0, hue: 0, gamma: 0, temperature: 0 };
    const LIMITS = {
        brightness: [-100, 100], contrast: [-100, 100], saturation: [-100, 100],
        hue: [-180, 180], gamma: [-100, 100], temperature: [-100, 100]
    };

    let state = loadProfile();
    let revision = Number(localStorage.getItem(REVISION_KEY) || '1') || 1;
    let currentVideo = null;
    let ui = null;
    let backend = { backend: 'local', revision: 0, ffmpegApplied: false, reason: '' };
    let syncTimer = 0;
    let networkDecorationInstalled = false;

    const diagnostics = {
        version: VERSION,
        state: 'initializing',
        networkHook: false,
        videoDetected: false,
        lastError: null,
        events: []
    };
    const diagnosticEvent = (event, details = {}) => {
        diagnostics.events.push({ at: new Date().toISOString(), event, ...details });
        diagnostics.events = diagnostics.events.slice(-30);
        console.info(`[JFIC] ${event}`, details);
    };
    window.JFICDiagnostics = () => ({ ...diagnostics, events: [...diagnostics.events] });
    window.addEventListener('error', event => {
        diagnostics.lastError = `${event.message} (${event.filename || 'inline'}:${event.lineno || 0})`;
        console.error('[JFIC] erreur JavaScript', event.error || event.message);
    });
    window.addEventListener('unhandledrejection', event => {
        diagnostics.lastError = String(event.reason || 'Unhandled promise rejection');
        console.error('[JFIC] promesse rejetee', event.reason);
    });

    const clientId = getOrCreateClientId();

    console.info(`[JFIC] interface chargee (${VERSION})`);

    function getOrCreateClientId() {
        let id = localStorage.getItem(CLIENT_KEY);
        if (!id) {
            id = (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`);
            localStorage.setItem(CLIENT_KEY, id);
        }
        return id;
    }

    function clamp(key, value) {
        const [min, max] = LIMITS[key];
        const n = Number(value);
        return Math.max(min, Math.min(max, Number.isFinite(n) ? n : 0));
    }

    function normalize(input = {}) {
        return Object.fromEntries(Object.keys(DEFAULTS).map(k => [k, clamp(k, input[k])]));
    }

    function loadProfile() {
        try { return normalize(JSON.parse(localStorage.getItem(PROFILE_KEY) || '{}')); }
        catch { return { ...DEFAULTS }; }
    }

    function saveProfile() {
        localStorage.setItem(PROFILE_KEY, JSON.stringify(state));
    }

    function hasActiveAdjustments(values = state) {
        return Object.values(values).some(value => Number(value) !== 0);
    }

    function bumpRevision() {
        revision += 1;
        localStorage.setItem(REVISION_KEY, String(revision));
        // An already-running FFmpeg process now contains stale values. Keep local preview
        // until a newly-created FFmpeg process confirms this exact revision.
        backend = { backend: 'local', revision: 0, ffmpegApplied: false, reason: 'Réglages modifiés; traitement local jusqu’au prochain flux FFmpeg.' };
    }

    function streamParams() {
        return {
            jficClientId: clientId,
            jficRevision: String(revision),
            imageBrightness: String(Math.round(state.brightness)),
            imageContrast: String(Math.round(state.contrast)),
            imageSaturation: String(Math.round(state.saturation)),
            imageHue: String(Math.round(state.hue)),
            imageGamma: String(Math.round(state.gamma)),
            imageTemperature: String(Math.round(state.temperature))
        };
    }

    function isVideoRequest(raw) {
        try {
            const u = new URL(raw, location.href);
            if (u.origin !== location.origin) return false;
            const text = `${u.pathname}${u.search}`;
            return /\/Videos\//i.test(u.pathname)
                && /(stream|master\.m3u8|main\.m3u8|\.m3u8|\.ts|\.mp4|\.webm)/i.test(text);
        } catch { return false; }
    }

    function decorateUrl(raw) {
        // With neutral values JFIC must be completely transparent: do not touch
        // Jellyfin's playback URL or its negotiation at all.
        if (!hasActiveAdjustments()) return raw;
        if (!isVideoRequest(raw)) return raw;
        try {
            const input = String(raw);
            const relative = !/^[a-z][a-z0-9+.-]*:/i.test(input);
            const u = new URL(input, location.href);
            for (const [key, value] of Object.entries(streamParams())) u.searchParams.set(key, value);
            return relative ? `${u.pathname}${u.search}${u.hash}` : u.toString();
        } catch { return raw; }
    }

    function installNetworkDecoration() {
        if (networkDecorationInstalled) return;
        networkDecorationInstalled = true;
        diagnostics.networkHook = true;
        diagnosticEvent('network-hook-installed');
        const nativeFetch = window.fetch?.bind(window);
        if (nativeFetch) {
            window.fetch = function (input, init) {
                try {
                    if (typeof input === 'string') input = decorateUrl(input);
                    else if (input instanceof Request && isVideoRequest(input.url)) input = new Request(decorateUrl(input.url), input);
                } catch { /* playback must never fail because of JFIC */ }
                return nativeFetch(input, init);
            };
        }

        const nativeOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (method, url, ...rest) {
            return nativeOpen.call(this, method, decorateUrl(url), ...rest);
        };
    }

    function ensureSvgFilter() {
        if (document.getElementById('jfic-svg-host')) return;
        const host = document.createElement('div');
        host.id = 'jfic-svg-host';
        host.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0">
          <filter id="jfic-image-filter" color-interpolation-filters="sRGB">
            <feColorMatrix id="jfic-temp" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"/>
            <feComponentTransfer>
              <feFuncR id="jfic-gr" type="gamma" amplitude="1" exponent="1" offset="0"/>
              <feFuncG id="jfic-gg" type="gamma" amplitude="1" exponent="1" offset="0"/>
              <feFuncB id="jfic-gb" type="gamma" amplitude="1" exponent="1" offset="0"/>
            </feComponentTransfer>
          </filter>
        </svg>`;
        document.body.appendChild(host);
    }

    function visibleVideo() {
        return [...document.querySelectorAll('video')].find(v => {
            const r = v.getBoundingClientRect();
            return r.width > 100 && r.height > 100 && getComputedStyle(v).visibility !== 'hidden';
        }) || null;
    }

    function serverOwnsCurrentRevision() {
        return backend.ffmpegApplied === true && Number(backend.revision) === Number(revision);
    }

    function effectiveLocalValues() {
        if (!serverOwnsCurrentRevision()) return state;
        // FFmpeg applies brightness/contrast/saturation/gamma/hue. Temperature stays local
        // because doing it blindly server-side is unsafe for HDR/color-space pipelines.
        return { ...DEFAULTS, temperature: state.temperature };
    }

    function updateSvg(localValues) {
        ensureSvgFilter();
        const exponent = 1 / Math.pow(2, localValues.gamma / 100);
        for (const id of ['jfic-gr', 'jfic-gg', 'jfic-gb']) {
            document.getElementById(id)?.setAttribute('exponent', exponent.toFixed(4));
        }

        const t = localValues.temperature / 100;
        const r = 1 + Math.max(0, t) * 0.12 + Math.min(0, t) * 0.05;
        const g = 1 - Math.abs(t) * 0.015;
        const b = 1 - Math.max(0, t) * 0.10 - Math.min(0, t) * 0.12;
        document.getElementById('jfic-temp')?.setAttribute(
            'values', `${r.toFixed(4)} 0 0 0 0  0 ${g.toFixed(4)} 0 0 0  0 0 ${b.toFixed(4)} 0 0  0 0 0 1 0`);
    }

    function cssFilter(v) {
        if (!hasActiveAdjustments(v)) return 'none';
        // Do not attach an SVG filter to the video element. Some Firefox/Chromium
        // GPU paths crash when an SVG filter is combined with hardware video decode.
        // Native CSS filters are simpler and remain reversible. CSS has no true
        // gamma or color-temperature primitive, so use safe visual approximations
        // locally; the server FFmpeg path still uses its exact eq/gamma filter.
        const gamma = Math.pow(2, v.gamma / 100);
        const warm = Math.max(0, v.temperature) / 100;
        const cool = Math.max(0, -v.temperature) / 100;
        const temperatureHue = warm * -8 + cool * 18;
        return `brightness(${Math.max(0, (1 + v.brightness / 100) * gamma)}) contrast(${Math.max(0, 1 + v.contrast / 100)}) saturate(${Math.max(0, (1 + v.saturation / 100) * (1 + cool * 0.22))}) hue-rotate(${v.hue + temperatureHue}deg) sepia(${(warm * 0.42).toFixed(3)})`;
    }

    function emitMpvBridge(localValues) {
        const payload = {
            source: 'jellyfin-image-controls',
            type: 'mpv-set-image-controls',
            version: VERSION,
            clientId,
            revision,
            // Same anti-double-filter rule as the HTML video path: when the current FFmpeg
            // revision is confirmed, native players receive neutral B/C/S/H/G and only the
            // client-only temperature component.
            values: { ...localValues }
        };
        window.postMessage(payload, '*');
        window.dispatchEvent(new CustomEvent('jfic:mpv', { detail: payload }));
    }

    function apply() {
        if (!currentVideo?.isConnected) currentVideo = visibleVideo();
        const localValues = effectiveLocalValues();
        if (currentVideo) {
            const filter = cssFilter(localValues);
            if (filter === 'none') currentVideo.style.removeProperty('filter');
            else currentVideo.style.setProperty('filter', filter, 'important');
        }
        emitMpvBridge(localValues);
        updateStatus();
    }

    function apiClient() {
        return window.ApiClient || window.apiClient || window.Emby?.ApiClient || null;
    }

    function currentUserId() {
        const api = apiClient();
        try {
            return api?.getCurrentUserId?.() || api?.currentUserId?.() || '';
        } catch { return ''; }
    }

    async function apiRequest(path, method = 'GET', body = null) {
        const api = apiClient();
        if (!api?.ajax) return null;
        try {
            const url = api.getUrl ? api.getUrl(path.replace(/^\//, '')) : path;
            return await api.ajax({
                type: method,
                url,
                data: body ? JSON.stringify(body) : undefined,
                contentType: body ? 'application/json' : undefined,
                dataType: 'json'
            });
        } catch { return null; }
    }

    async function pollBackend() {
        if (!currentVideo) return;
        const result = await apiRequest(`/ImageControls/PlaybackStatus?clientId=${encodeURIComponent(clientId)}`);
        if (result) {
            const nextBackend = {
                backend: result.backend ?? result.Backend ?? 'local',
                revision: Number(result.revision ?? result.Revision ?? 0),
                ffmpegApplied: Boolean(result.ffmpegApplied ?? result.FfmpegApplied),
                reason: result.reason ?? result.Reason ?? ''
            };
            const changed = backend.backend !== nextBackend.backend
                || backend.revision !== nextBackend.revision
                || backend.ffmpegApplied !== nextBackend.ffmpegApplied
                || backend.reason !== nextBackend.reason;
            backend = nextBackend;
            if (changed) diagnosticEvent('backend-status', backend);
            apply();
        }
    }

    async function loadServerProfile() {
        const userId = currentUserId();
        if (!userId) return;
        const result = await apiRequest(`/ImageControls/Profile?userId=${encodeURIComponent(userId)}&clientId=${encodeURIComponent(clientId)}`);
        const values = result?.values ?? result?.Values;
        if (values) {
            state = normalize({
                brightness: values.brightness ?? values.Brightness,
                contrast: values.contrast ?? values.Contrast,
                saturation: values.saturation ?? values.Saturation,
                hue: values.hue ?? values.Hue,
                gamma: values.gamma ?? values.Gamma,
                temperature: values.temperature ?? values.Temperature
            });
            saveProfile();
            refreshControls();
            apply();
        }
    }

    async function saveServerProfile() {
        const userId = currentUserId();
        if (!userId) return false;
        const scope = ui?.panel.querySelector('.jfic-scope')?.value || 'device';
        return (await apiRequest('/ImageControls/Profile', 'PUT', { userId, clientId, scope, values: state })) !== null;
    }

    function scheduleServerSave() {
        clearTimeout(syncTimer);
        syncTimer = setTimeout(() => saveServerProfile(), 1200);
    }

    const fields = [
        ['brightness', 'Luminosité', -100, 100],
        ['contrast', 'Contraste', -100, 100],
        ['saturation', 'Saturation', -100, 100],
        ['hue', 'Teinte', -180, 180],
        ['gamma', 'Gamma', -100, 100],
        ['temperature', 'Température', -100, 100]
    ];

    function formatValue(key, value) {
        if (key === 'hue') return `${value}°`;
        return value > 0 ? `+${value}` : String(value);
    }

    function createUi() {
        if (ui || !document.body) return;

        const launcher = document.createElement('button');
        launcher.id = 'jfic-launcher';
        launcher.type = 'button';
        launcher.innerHTML = '<span class="jfic-launcher-icon material-icons" aria-hidden="true">palette</span>';
        launcher.title = "Réglages de l'image";
        launcher.setAttribute('aria-label', "Réglages de l'image");
        launcher.style.width = '2.75rem';
        launcher.style.height = '2.75rem';
        launcher.style.padding = '0';
        launcher.style.marginLeft = '0';
        launcher.querySelector('.jfic-launcher-icon').style.fontSize = '1.5rem';
        launcher.querySelector('.jfic-launcher-icon').style.lineHeight = '1';

        const panel = document.createElement('section');
        panel.id = 'jfic-panel';
        panel.innerHTML = `
          <div class="jfic-header">
            <div><div class="jfic-title">Réglages de l’image</div><div class="jfic-version">JFIC ${VERSION}</div></div>
            <button class="jfic-close" type="button" aria-label="Fermer">✕</button>
          </div>
          <div class="jfic-mode"><span class="jfic-mode-dot"></span><span class="jfic-mode-text">Local</span></div>
          <div class="jfic-controls"></div>
          <div class="jfic-options">
            <label>Profil <select class="jfic-scope"><option value="device">Cet appareil</option><option value="user">Mon compte</option></select></label>
          </div>
          <div class="jfic-footer">
            <button class="jfic-reset" type="button">Réinitialiser</button>
            <button class="jfic-save" type="button">Enregistrer</button>
          </div>
          <div class="jfic-status"></div>`;

        const controls = panel.querySelector('.jfic-controls');
        for (const [key, label, min, max] of fields) {
            const row = document.createElement('div');
            row.className = 'jfic-row';
            row.dataset.key = key;
            row.innerHTML = `<label>${label}</label><input type="range" min="${min}" max="${max}" step="1" value="${state[key]}"><input class="jfic-value" type="text" inputmode="numeric" aria-label="Valeur ${label}" value="${formatValue(key, state[key])}">`;
            const input = row.querySelector('input[type="range"]');
            const valueInput = row.querySelector('.jfic-value');
            valueInput.style.boxSizing = 'border-box';
            valueInput.style.width = '3.4rem';
            valueInput.style.border = '1px solid rgba(255,255,255,.14)';
            valueInput.style.borderRadius = '.35rem';
            valueInput.style.padding = '.2rem .3rem';
            valueInput.style.background = 'rgba(255,255,255,.08)';
            valueInput.style.color = 'inherit';
            valueInput.style.font = 'inherit';
            input.addEventListener('input', () => {
                state[key] = clamp(key, input.value);
                valueInput.value = formatValue(key, state[key]);
                if (hasActiveAdjustments()) installNetworkDecoration();
                diagnosticEvent('adjustment-changed', { key, value: state[key] });
                bumpRevision();
                saveProfile();
                apply();
                scheduleServerSave();
            });

            let pointerDragging = false;
            const updateRangeFromPointer = event => {
                const rect = input.getBoundingClientRect();
                if (!rect.width) return;
                const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
                const minValue = Number(input.min);
                const maxValue = Number(input.max);
                input.value = String(Math.round(minValue + ratio * (maxValue - minValue)));
                input.dispatchEvent(new Event('input', { bubbles: true }));
            };
            input.addEventListener('pointerdown', event => {
                pointerDragging = true;
                input.focus({ preventScroll: true });
                input.setPointerCapture?.(event.pointerId);
                updateRangeFromPointer(event);
                event.preventDefault();
            });
            input.addEventListener('pointermove', event => {
                if (pointerDragging) updateRangeFromPointer(event);
            });
            const stopPointerDragging = event => {
                pointerDragging = false;
                if (input.hasPointerCapture?.(event.pointerId)) input.releasePointerCapture(event.pointerId);
            };
            input.addEventListener('pointerup', stopPointerDragging);
            input.addEventListener('pointercancel', stopPointerDragging);

            const commitTextValue = () => {
                const raw = valueInput.value.replace(/[^0-9+.-]/g, '');
                const numeric = Number(raw);
                state[key] = clamp(key, Number.isFinite(numeric) ? numeric : 0);
                input.value = String(state[key]);
                valueInput.value = formatValue(key, state[key]);
                if (hasActiveAdjustments()) installNetworkDecoration();
                diagnosticEvent('adjustment-changed', { key, value: state[key], source: 'keyboard' });
                bumpRevision();
                saveProfile();
                apply();
                scheduleServerSave();
            };
            valueInput.addEventListener('input', () => {
                const raw = valueInput.value.replace(/[^0-9+.-]/g, '');
                const numeric = Number(raw);
                if (raw && Number.isFinite(numeric)) {
                    state[key] = clamp(key, numeric);
                    input.value = String(state[key]);
                    apply();
                }
            });
            valueInput.addEventListener('keydown', event => {
                if (event.key === 'Enter') {
                    event.preventDefault();
                    valueInput.blur();
                }
            });
            valueInput.addEventListener('blur', commitTextValue);
            controls.appendChild(row);
        }

        launcher.addEventListener('click', () => panel.classList.toggle('jfic-open'));
        panel.querySelector('.jfic-close').addEventListener('click', () => panel.classList.remove('jfic-open'));
        panel.querySelector('.jfic-reset').addEventListener('click', () => {
            state = { ...DEFAULTS };
            bumpRevision();
            saveProfile();
            refreshControls();
            apply();
            scheduleServerSave();
        });
        panel.querySelector('.jfic-save').addEventListener('click', async () => {
            saveProfile();
            const ok = await saveServerProfile();
            setStatusMessage(ok ? 'Profil enregistré sur le serveur.' : 'Profil local enregistré; API plugin indisponible.');
        });

        // Keep the panel in the document, but attach the launcher only to Jellyfin's
        // native OSD controls through mountLauncher(). It must not exist as a body-level
        // floating control during player transitions.
        document.body.append(panel);
        ui = { launcher, panel };
        refreshControls();
        updateStatus();
    }

    function findOsdButtonContainer() {
        return document.querySelector('.osdControls .buttons.focuscontainer-x');
    }

    function mountLauncher() {
        if (!ui) return;
        const buttonContainer = findOsdButtonContainer();
        if (!buttonContainer) {
            // The launcher must never float outside Jellyfin's native OSD button row.
            ui.launcher.classList.remove('jfic-visible');
            return;
        }

        const settingsButton = buttonContainer.querySelector('.btnVideoOsdSettings');
        if (settingsButton) {
            // Jellyfin rebuilds this row while playback starts and can append
            // unknown buttons at the end. Reinsert JFIC before the current next
            // sibling every time the native row changes.
            if (settingsButton.nextElementSibling !== ui.launcher
                || ui.launcher.parentElement !== buttonContainer) {
                buttonContainer.insertBefore(ui.launcher, settingsButton.nextElementSibling);
            }
            // Jellyfin's OSD row is flex-based. Its native buttons can retain a
            // visual order independent of DOM order, so explicitly keep JFIC
            // between Settings and the remaining right-side actions.
            settingsButton.style.setProperty('order', '100', 'important');
            ui.launcher.style.setProperty('order', '101', 'important');
            for (const [selector, order] of [
                ['.btnAirPlay', '102'],
                ['.btnPip', '103'],
                ['.btnFullscreen', '104']
            ]) {
                buttonContainer.querySelector(selector)?.style.setProperty('order', order, 'important');
            }
        } else if (ui.launcher.parentElement !== buttonContainer) {
            // Jellyfin can create the settings button a moment after the row.
            // Temporarily append into the same row; the next tick will place it
            // immediately after btnVideoOsdSettings when that button appears.
            buttonContainer.appendChild(ui.launcher);
        }
        ui.launcher.classList.add('jfic-visible');
    }

    function refreshControls() {
        if (!ui) return;
        for (const row of ui.panel.querySelectorAll('.jfic-row')) {
            const key = row.dataset.key;
            row.querySelector('input').value = state[key];
            row.querySelector('.jfic-value').value = formatValue(key, state[key]);
        }
    }

    function setStatusMessage(message) {
        const el = ui?.panel.querySelector('.jfic-status');
        const technicalBackendMessage = /No active FFmpeg|Existing |Direct Play|transcodage|FFmpeg|NVENC|backend non/i.test(String(message));
        const userMessage = technicalBackendMessage
            ? (serverOwnsCurrentRevision() ? "Reglages d'image actifs." : 'Reglages locaux.')
            : message;
        if (el && el.textContent !== userMessage) el.textContent = userMessage;
    }

    function updateStatus() {
        if (!ui) return;
        const activeFfmpeg = serverOwnsCurrentRevision();
        const text = ui.panel.querySelector('.jfic-mode-text');
        if (activeFfmpeg) {
            const modeText = backend.backend === 'ffmpeg-nvenc' ? 'FFmpeg / NVENC (déjà actif)' : 'FFmpeg (transcodage déjà actif)';
            if (text.textContent !== modeText) text.textContent = modeText;
            setStatusMessage(backend.backend === 'ffmpeg-nvenc'
                ? 'Luminosité/contraste/saturation/gamma/teinte : FFmpeg dans le transcodage NVENC existant. Si la surface est CUDA, JFIC fait un copy-back contrôlé puis renvoie vers CUDA/NVENC. Température : locale.'
                : 'Luminosité/contraste/saturation/gamma/teinte : FFmpeg. Température : locale. Aucun transcodage n’est déclenché par JFIC.');
        } else {
            if (text.textContent !== 'Traitement local') text.textContent = 'Traitement local';
            setStatusMessage(backend.reason || 'Direct Play / copie vidéo / backend non confirmé : correction locale, sans demander de transcodage.');
        }
    }

    function tick() {
        const next = visibleVideo();
        if (currentVideo && next !== currentVideo) currentVideo.style.removeProperty('filter');
        currentVideo = next;
        const wasVideoDetected = diagnostics.videoDetected;
        diagnostics.videoDetected = Boolean(currentVideo);
        if (wasVideoDetected !== diagnostics.videoDetected) {
            diagnosticEvent(diagnostics.videoDetected ? 'video-detected' : 'video-removed');
        }
        // The launcher belongs exclusively to Jellyfin's OSD controls. During player
        // transitions the container may not exist yet, so keep it hidden until it
        // can be mounted there.
        mountLauncher();
        if (!currentVideo) ui?.panel.classList.remove('jfic-open');
        else apply();
    }

    function boot() {
        try {
            diagnosticEvent('boot-start');
            // Important: do not wrap fetch/XHR during normal playback. The hook is
            // installed lazily only after the user changes a slider.
            createUi();
            diagnosticEvent('ui-created', { launcher: Boolean(document.getElementById('jfic-launcher')) });
            tick();
            setTimeout(loadServerProfile, 2000);
            setInterval(pollBackend, 1500);
            setInterval(tick, 1200);
            new MutationObserver(mutations => {
                // Ignore child-list mutations caused by JFIC's own status panel.
                // Otherwise updateStatus() -> MutationObserver -> tick() loops forever
                // as soon as a video element is mounted.
                const ownPanel = ui?.panel;
                const externalMutation = mutations.some(mutation => !ownPanel || !ownPanel.contains(mutation.target));
                if (externalMutation) tick();
            }).observe(document.documentElement, { childList: true, subtree: true });
            diagnostics.state = 'ready';
            diagnosticEvent('boot-ready', { videoDetected: diagnostics.videoDetected });
        } catch (error) {
            diagnostics.state = 'failed';
            diagnostics.lastError = String(error?.stack || error);
            console.error('[JFIC] boot failed', error);
        }
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
    else boot();
})();
