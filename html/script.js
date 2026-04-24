// ════════════════════════════════════════════════════════════
// COREX Events HUD · renders banner cards for active events
// ════════════════════════════════════════════════════════════

const state = {
    events: new Map(),      // id → server state
    domEls: new Map(),      // id → root <div>
    distance: new Map(),    // id → meters
};

const listEl = document.getElementById('events-list');

// Icon mapping — event type → FA icon class
const ICONS = {
    supply_drop:     'fa-helicopter',
    trader_caravan:  'fa-truck',
    zombie_outbreak: 'fa-skull',
    safe_zone:       'fa-shield',
    default:         'fa-bolt',
};

// ── Utility ─────────────────────────────────────────────────
function fmtDuration(sec) {
    if (sec <= 0) return '00:00';
    sec = Math.floor(sec);
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

function fmtDistance(m) {
    if (m == null) return null;
    if (m < 1000) return `${m}m`;
    return `${(m / 1000).toFixed(1)}km`;
}

function phaseOf(ev) {
    // Before dropAt → "incoming" countdown toward drop
    // After dropAt, before endAt → "live" countdown toward end
    const now = Math.floor(Date.now() / 1000);
    const localNow = now; // falls back to wall clock if server time not synced
    if (ev.dropAt && localNow < ev.dropAt) return 'incoming';
    return 'live';
}

// ── DOM construction ────────────────────────────────────────
function buildCard(ev) {
    const root = document.createElement('div');
    root.className = 'ev severity-' + (ev.severity || 'info');
    root.dataset.id = ev.id;

    const iconClass = ICONS[ev.type] || ICONS.default;

    root.innerHTML = `
        <div class="ev-bar"></div>
        <div class="ev-head">
            <div class="ev-icon"><i class="fa-solid ${iconClass}"></i></div>
            <div class="ev-cat">
                <span class="ev-cat-main">World Event</span>
                <span class="ev-cat-sub">${(ev.type || '').toUpperCase()}</span>
            </div>
            <div class="ev-status">
                <span class="ev-status-dot"></span>
                <span class="ev-status-txt">Incoming</span>
            </div>
        </div>
        <div class="ev-body">
            <div class="ev-title">${escape(ev.label || 'Event')}</div>
            <div class="ev-desc">${escape(ev.description || '')}</div>
        </div>
        <div class="ev-meta">
            <div class="ev-loc">
                <i class="fa-solid fa-location-dot"></i>
                <span class="ev-loc-name">${escape(ev.locationName || 'Unknown location')}</span>
            </div>
            <div class="ev-dist">—</div>
        </div>
        <div class="ev-foot">
            <div class="ev-time-row">
                <span class="ev-time-k">Time remaining</span>
                <span class="ev-time-v">--:--</span>
            </div>
            <div class="ev-progress">
                <div class="ev-progress-fill" style="width: 0%"></div>
            </div>
        </div>
    `;

    // Cache DOM refs once — avoids 5 querySelector calls per event per tick
    root._refs = {
        statusTxt: root.querySelector('.ev-status-txt'),
        timeV:     root.querySelector('.ev-time-v'),
        timeK:     root.querySelector('.ev-time-k'),
        fill:      root.querySelector('.ev-progress-fill'),
        dist:      root.querySelector('.ev-dist'),
    };

    return root;
}

function escape(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

const MAX_VISIBLE = 3;

function applyVisibilityLimit() {
    if (!listEl) return;
    const cards = Array.from(listEl.children).filter(c => !c.classList.contains('exit'));
    cards.forEach((card, i) => {
        const isOverflow = i >= MAX_VISIBLE;
        card.classList.toggle('hidden-overflow', isOverflow);
    });
}

// ── State transitions ───────────────────────────────────────
function addEvent(ev) {
    if (state.events.has(ev.id)) {
        updateEventFull(ev);
        return;
    }
    const card = buildCard(ev);
    listEl.prepend(card);
    state.events.set(ev.id, ev);
    state.domEls.set(ev.id, card);
    renderPhase(ev.id);
    applyVisibilityLimit();
}

function updateEventFull(ev) {
    const prev = state.events.get(ev.id);
    state.events.set(ev.id, Object.assign({}, prev || {}, ev));
    renderPhase(ev.id);
}

function patchEvent(id, patch) {
    const prev = state.events.get(id);
    if (!prev) return;
    const merged = Object.assign({}, prev, patch || {});
    state.events.set(id, merged);
    renderPhase(id);
}

function removeEvent(id, reason) {
    const el = state.domEls.get(id);
    if (!el) return;
    el.classList.add('exit');
    setTimeout(() => {
        el.remove();
        state.domEls.delete(id);
        state.events.delete(id);
        state.distance.delete(id);
        applyVisibilityLimit();
    }, 220);
}

// ── Rendering ──────────────────────────────────────────────
function renderPhase(id) {
    const ev = state.events.get(id);
    const el = state.domEls.get(id);
    if (!ev || !el) return;

    const phase = phaseOf(ev);
    el.classList.toggle('is-incoming', phase === 'incoming');
    el.classList.toggle('is-live',     phase === 'live');

    const refs = el._refs;
    if (refs && refs.statusTxt) refs.statusTxt.textContent = phase === 'incoming' ? 'Incoming' : 'Live';
}

function renderTick(id) {
    const ev = state.events.get(id);
    const el = state.domEls.get(id);
    if (!ev || !el) return;

    const now = Math.floor(Date.now() / 1000);
    const phase = phaseOf(ev);

    let remaining, total, targetAt;
    if (phase === 'incoming') {
        targetAt  = ev.dropAt;
        total     = (ev.dropAt || now) - (ev.startTime || now);
        remaining = Math.max(0, targetAt - now);
    } else {
        targetAt  = (ev.startTime || now) + (ev.duration || 0);
        total     = ev.duration || 1;
        remaining = Math.max(0, targetAt - now);
    }

    const refs = el._refs || {};

    const newTimeTxt = fmtDuration(remaining);
    if (refs.timeV && refs.timeV.textContent !== newTimeTxt) refs.timeV.textContent = newTimeTxt;

    if (refs.fill) {
        const pct = phase === 'incoming'
            ? (1 - (remaining / Math.max(1, total))) * 100
            : (remaining / Math.max(1, total)) * 100;
        const clamped = Math.max(0, Math.min(100, pct));
        const nextW = clamped.toFixed(1) + '%';
        if (refs.fill._w !== nextW) {
            refs.fill.style.width = nextW;
            refs.fill._w = nextW;
        }
    }

    const newTimeK = phase === 'incoming' ? 'Landing in' : 'Time remaining';
    if (refs.timeK && refs.timeK.textContent !== newTimeK) refs.timeK.textContent = newTimeK;

    const dist = state.distance.get(id);
    const newDist = dist != null ? fmtDistance(dist) : '—';
    if (refs.dist && refs.dist.textContent !== newDist) refs.dist.textContent = newDist;

    // Phase transition detection
    if (phase === 'live' && !el.classList.contains('is-live')) renderPhase(id);
}

// ── Message bus ────────────────────────────────────────────
window.addEventListener('message', (e) => {
    const msg = e.data || {};
    switch (msg.action) {
        case 'init':
            break;
        case 'addEvent':
            if (msg.data) addEvent(msg.data);
            break;
        case 'updateEvent':
            if (msg.data && msg.data.id) patchEvent(msg.data.id, msg.data.patch);
            break;
        case 'removeEvent':
            if (msg.data && msg.data.id) removeEvent(msg.data.id, msg.data.reason);
            break;
        case 'tick':
            if (msg.data && Array.isArray(msg.data.events)) {
                for (const t of msg.data.events) {
                    if (t.distance != null) state.distance.set(t.id, t.distance);
                    renderTick(t.id);
                }
            }
            break;
    }
});

// Fallback internal tick every second so countdown still advances
// even if the server stops sending ticks for a moment. Early-exit when
// there are no events so we don't pay for an empty loop forever.
setInterval(() => {
    if (state.events.size === 0) return;
    for (const id of state.events.keys()) renderTick(id);
}, 1000);
