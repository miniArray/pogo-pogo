/* Browser shell: touch controls, settings and file pickers. Game rules stay in GDScript. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const canvas = $('canvas');
  const controller = $('controller');
  const settings = $('settings');
  const pad = window.pogoPad = {buttons: 0};
  const pointers = new Map();
  let ready = false;
  const queue = [];

  function act(...args) {
    if (ready && typeof window.pogoAction === 'function') window.pogoAction(...args);
    else queue.push(args);
  }

  window.pogoShell = {
    started() {
      ready = true;
      const wait = () => {
        if (typeof window.pogoAction !== 'function') { setTimeout(wait, 50); return; }
        while (queue.length) window.pogoAction(...queue.shift());
        restoreDisplay();
        canvas.focus({preventScroll: true});
      };
      wait();
    },
  };

  window.pogoDownload = (name, base64) => {
    const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([bytes], {type: 'application/json'}));
    link.download = name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  };

  // Touch controls: each pointer presses the button under it; sliding moves the press.
  function publish() {
    let mask = 0;
    for (const button of pointers.values()) if (button) mask |= Number(button.dataset.mask);
    pad.buttons = mask;
    for (const button of controller.querySelectorAll('button[data-mask]')) {
      button.classList.toggle('held', (mask & Number(button.dataset.mask)) !== 0);
    }
  }
  function buttonAt(event) {
    const element = document.elementFromPoint(event.clientX, event.clientY);
    return element && element.closest && element.closest('#controller button[data-mask]');
  }
  controller.addEventListener('pointerdown', event => {
    event.preventDefault();
    controller.setPointerCapture?.(event.pointerId);
    pointers.set(event.pointerId, buttonAt(event));
    publish();
  });
  controller.addEventListener('pointermove', event => {
    if (!pointers.has(event.pointerId)) return;
    pointers.set(event.pointerId, buttonAt(event));
    publish();
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    controller.addEventListener(type, event => { pointers.delete(event.pointerId); publish(); });
  }
  controller.addEventListener('contextmenu', event => event.preventDefault());
  function releaseAll() { pointers.clear(); publish(); }
  window.addEventListener('blur', releaseAll);
  document.addEventListener('visibilitychange', () => { if (document.hidden) releaseAll(); });

  function showController(show) {
    controller.hidden = !show;
    $('toggle-pad').setAttribute('aria-pressed', String(show));
    try { localStorage.setItem('pogo-touch', String(show)); } catch (_) { /* storage may be blocked */ }
  }
  $('toggle-pad').addEventListener('click', () => { showController(controller.hidden); canvas.focus({preventScroll: true}); });
  let showTouch = 'ontouchstart' in window;
  try { const saved = localStorage.getItem('pogo-touch'); if (saved !== null) showTouch = saved === 'true'; } catch (_) { /* default */ }
  showController(showTouch);

  $('settings-button').addEventListener('click', () => {
    settings.hidden = !settings.hidden;
    $('settings-button').setAttribute('aria-expanded', String(!settings.hidden));
    if (settings.hidden) canvas.focus({preventScroll: true});
  });
  settings.addEventListener('keydown', event => event.stopPropagation());
  $('reset-button').addEventListener('click', () => { act('reset'); canvas.focus({preventScroll: true}); });
  $('course-play').addEventListener('click', () => act('course', Number($('course-select').value)));
  $('course-save').addEventListener('click', () => act('course_save'));
  $('course-load').addEventListener('click', () => $('course-file').click());
  $('pack-load').addEventListener('click', () => $('pack-file').click());
  $('pack-clear').addEventListener('click', () => { act('pack_clear'); });

  function readBase64(file, then) {
    const reader = new FileReader();
    reader.onload = () => {
      const bytes = new Uint8Array(reader.result);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      then(btoa(binary));
    };
    reader.readAsArrayBuffer(file);
  }
  $('course-file').addEventListener('change', event => {
    const file = event.target.files[0];
    if (file) readBase64(file, data => act('course_json', data));
    event.target.value = '';
  });
  $('pack-file').addEventListener('change', event => {
    const file = event.target.files[0];
    if (file) readBase64(file, data => act('pack', data));
    event.target.value = '';
  });

  function restoreDisplay() {
    let saved = {};
    try { saved = JSON.parse(localStorage.getItem('pogo-display') || '{}'); } catch (_) { /* default */ }
    if (saved.mode) $('display-mode').value = saved.mode;
    if (typeof saved.sharp === 'boolean') $('sharp').checked = saved.sharp;
    if (typeof saved.muted === 'boolean') $('muted').checked = saved.muted;
    applyDisplay();
    act('mute', $('muted').checked);
  }
  function applyDisplay() {
    act('display', $('display-mode').value, $('sharp').checked);
    try {
      localStorage.setItem('pogo-display', JSON.stringify({mode: $('display-mode').value, sharp: $('sharp').checked, muted: $('muted').checked}));
    } catch (_) { /* storage may be blocked */ }
  }
  $('display-mode').addEventListener('change', applyDisplay);
  $('sharp').addEventListener('change', applyDisplay);
  $('muted').addEventListener('change', () => { act('mute', $('muted').checked); applyDisplay(); });

  // The canvas backing store follows the stage box; Godot reads its size.
  const stage = $('stage');
  function resize() {
    const ratio = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(stage.clientWidth * ratio));
    const height = Math.max(1, Math.round(stage.clientHeight * ratio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
  }
  new ResizeObserver(resize).observe(stage);
  window.addEventListener('resize', resize);
  resize();

  // Reflect the game's own state for the pack line.
  setInterval(() => {
    if (!window.pogoStateJSON) return;
    const state = JSON.parse(window.pogoStateJSON);
    $('pack-state').textContent = state.pack === 'placeholder' ? 'No pack: placeholder shapes.' : `Using pack: ${state.pack}`;
  }, 500);
})();
