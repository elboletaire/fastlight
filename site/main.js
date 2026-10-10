// Hero query switcher: cycles the real panel renders. Content works without it.
(() => {
  const stage = document.querySelector('[data-stage]');
  const chipsBox = stage && stage.querySelector('[data-chips]');
  if (!stage || !chipsBox) return;

  const chips = [...chipsBox.querySelectorAll('.chip')];
  const shots = new Map([...stage.querySelectorAll('[data-shot]')].map((img) => [img.dataset.shot, img]));
  const label = stage.querySelector('.stage-label');
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  const CYCLE = 5000;
  let index = 0;
  let timer = 0;
  let paused = false;
  let visible = true;

  chipsBox.hidden = false;
  chipsBox.style.setProperty('--cycle', `${CYCLE}ms`);
  if (label) label.hidden = false;

  // Load the other renders once the page is idle, so switching is instant.
  const warm = () => stage.querySelectorAll('img').forEach((img) => { img.loading = 'eager'; });
  if ('requestIdleCallback' in window) requestIdleCallback(warm, { timeout: 3000 });
  else setTimeout(warm, 1500);

  const show = (i) => {
    index = (i + chips.length) % chips.length;
    chips.forEach((chip, n) => {
      const on = n === index;
      chip.setAttribute('aria-pressed', String(on));
      chip.classList.remove('is-timing');
      const shot = shots.get(chip.dataset.for);
      if (shot) {
        shot.classList.toggle('is-active', on);
        shot.setAttribute('aria-hidden', String(!on));
      }
    });
  };

  const stop = () => {
    clearTimeout(timer);
    chips.forEach((chip) => chip.classList.remove('is-timing'));
  };

  const schedule = () => {
    stop();
    if (paused || !visible || reduce.matches || document.hidden) return;
    const chip = chips[index];
    void chip.offsetWidth; // restart the progress bar
    chip.classList.add('is-timing');
    timer = setTimeout(() => { show(index + 1); schedule(); }, CYCLE);
  };

  chips.forEach((chip, n) => {
    chip.addEventListener('click', () => {
      show(n);
      paused = true; // the visitor took over; stop auto-cycling
      stop();
    });
  });

  stage.addEventListener('pointerenter', () => { if (!paused) stop(); });
  stage.addEventListener('pointerleave', () => { if (!paused) schedule(); });
  stage.addEventListener('focusin', () => { paused = true; stop(); });
  document.addEventListener('visibilitychange', schedule);
  reduce.addEventListener?.('change', schedule);

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      schedule();
    }, { threshold: 0.3 }).observe(stage);
  }

  show(0);
  schedule();
})();
