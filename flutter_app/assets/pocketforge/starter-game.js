/* PocketForge starter: real deterministic game logic, exposed for repeatable agent tests. */
(function (scope) {
  'use strict';
  class NeonRun {
    constructor(seed = 173) { this.seed = seed; this.reset(); }
    reset() {
      this.randomState = this.seed; this.running = false; this.paused = false;
      this.lane = 0; this.carX = 0; this.distance = 0; this.score = 0;
      this.shield = 3; this.speed = 0; this.elapsed = 0; this.spawnIn = 1.5;
      this.obstacles = []; this.hitPulse = 0; this.passed = 0; this.nextId = 1;
    }
    random() { this.randomState = (Math.imul(this.randomState, 1664525) + 1013904223) >>> 0; return this.randomState / 4294967296; }
    start() { this.reset(); this.running = true; }
    steer(direction) { if (this.running && !this.paused) this.lane = Math.max(-1, Math.min(1, this.lane + Math.sign(direction))); }
    togglePause() { if (this.running) this.paused = !this.paused; }
    addObstacle(lane, z = 0) { this.obstacles.push({ id: this.nextId++, lane, z, handled: false }); }
    step(seconds) {
      if (!this.running || this.paused) return;
      const dt = Math.max(0, Math.min(Number(seconds) || 0, .05));
      this.elapsed += dt; this.speed = Math.min(240, 95 + this.elapsed * 2.8);
      this.carX += (this.lane - this.carX) * Math.min(1, dt * 13);
      this.distance += this.speed / 3.6 * dt;
      this.hitPulse = Math.max(0, this.hitPulse - dt * 3);
      this.spawnIn -= dt;
      if (this.spawnIn <= 0) { this.addObstacle(Math.floor(this.random() * 3) - 1); this.spawnIn = Math.max(.75, 1.65 - this.elapsed * .008); }
      for (const obstacle of this.obstacles) {
        obstacle.z += dt * (this.speed / 190);
        if (!obstacle.handled && obstacle.z >= .91) {
          obstacle.handled = true;
          if (Math.abs(obstacle.lane - this.carX) < .48) {
            this.shield -= 1; this.hitPulse = 1;
            if (this.shield <= 0) { this.shield = 0; this.running = false; }
          } else { this.passed += 1; }
        }
      }
      this.obstacles = this.obstacles.filter(item => item.z < 1.25);
      this.score = Math.floor(this.distance) + this.passed * 50;
    }
    advance(seconds) {
      let remaining = Math.max(0, Math.min(Number(seconds) || 0, 180));
      while (remaining > 0 && this.running && !this.paused) { const dt = Math.min(1 / 60, remaining); this.step(dt); remaining -= dt; }
      return this.snapshot();
    }
    snapshot() {
      return { running: this.running, paused: this.paused, lane: this.lane, carX: this.carX,
        distance: Math.floor(this.distance), score: this.score, shield: this.shield,
        speed: Math.floor(this.speed), elapsed: Number(this.elapsed.toFixed(3)), passed: this.passed,
        obstacles: this.obstacles.map(item => ({ lane: item.lane, z: Number(item.z.toFixed(3)), handled: item.handled })) };
    }
  }
  scope.NeonRun = NeonRun;
  if (typeof module !== 'undefined') module.exports = { NeonRun };
  if (typeof document === 'undefined') return;

  const simulation = new NeonRun();
  const canvas = document.querySelector('#race'), ctx = canvas.getContext('2d');
  const overlay = document.querySelector('#overlay'), status = document.querySelector('#status');
  const pause = document.querySelector('#pause');
  let w = 640, h = 560, previous = performance.now(), ambient = 0;
  function resize() {
    const bounds = canvas.getBoundingClientRect(); w = Math.max(1, bounds.width); h = Math.max(1, bounds.height);
    const scale = Math.min(2, scope.devicePixelRatio || 1);
    canvas.width = Math.round(w * scale); canvas.height = Math.round(h * scale); ctx.setTransform(scale, 0, 0, scale, 0, 0);
  }
  function polygon(points, color) { ctx.fillStyle = color; ctx.beginPath(); points.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.closePath(); ctx.fill(); }
  function projection(z) { const p = Math.max(0, z); return { y: h * .36 + Math.pow(p, 1.8) * h * .64, half: w * (.018 + Math.pow(p, 1.3) * .59) }; }
  function render() {
    const state = simulation;
    const sky = ctx.createLinearGradient(0, 0, 0, h); sky.addColorStop(0, '#080c20'); sky.addColorStop(.45, '#3a174c'); sky.addColorStop(1, '#080b15');
    ctx.fillStyle = sky; ctx.fillRect(0, 0, w, h);
    const sunX = w * .62, sunY = h * .245, sunR = Math.min(w, h) * .125;
    const sun = ctx.createLinearGradient(0, sunY - sunR, 0, sunY + sunR); sun.addColorStop(0, '#ffbb93'); sun.addColorStop(1, '#ca397d');
    ctx.fillStyle = sun; ctx.beginPath(); ctx.arc(sunX, sunY, sunR, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#2c1740'; for (let i = 0; i < 6; i++) { const y = sunY + i * sunR * .15; ctx.fillRect(sunX - sunR - 1, y, sunR * 2 + 2, 1 + i * 1.2); }
    for (let i = 0; i < 26; i++) { const bw = w / 23; const bh = 13 + ((i * 47) % 81); ctx.fillStyle = '#101125'; ctx.fillRect(i * bw - bw / 2, h * .36 - bh, bw * .85, bh); ctx.fillStyle = '#713d80'; ctx.fillRect(i * bw - bw / 2 + bw * .15, h * .36 - bh + 7, 2, 3); }
    const shift = -state.carX * w * .025;
    polygon([[w / 2 + shift - w * .018, h * .36], [w / 2 + shift + w * .018, h * .36], [w * 1.1, h], [-w * .1, h]], '#11131e');
    for (let i = 0; i < 22; i++) {
      const z = ((i / 22) + ambient * .21) % 1; const p = projection(z);
      ctx.strokeStyle = `rgba(171,78,166,${.12 + z * .4})`; ctx.lineWidth = .6 + z;
      ctx.beginPath(); ctx.moveTo(0, p.y); ctx.lineTo(w, p.y); ctx.stroke();
    }
    for (const fraction of [-1, -1 / 3, 1 / 3, 1]) {
      const a = projection(0), b = projection(1);
      ctx.strokeStyle = Math.abs(fraction) === 1 ? '#a06ede' : '#536b75'; ctx.lineWidth = Math.abs(fraction) === 1 ? 2 : 1;
      ctx.beginPath(); ctx.moveTo(w / 2 + shift + a.half * fraction, a.y); ctx.lineTo(w / 2 + b.half * fraction, b.y); ctx.stroke();
    }
    for (const obstacle of [...state.obstacles].sort((a, b) => a.z - b.z)) {
      const p = projection(obstacle.z), x = w / 2 + shift + obstacle.lane * p.half * .65;
      const size = Math.max(4, p.half * .3), top = p.y - size * .65;
      ctx.shadowColor = '#ff6488'; ctx.shadowBlur = size * .16;
      polygon([[x - size / 2, top], [x + size / 2, top], [x + size / 2, p.y], [x - size / 2, p.y]], '#ce3a68');
      ctx.fillStyle = '#ffa8bd'; ctx.fillRect(x - size / 2, top, size, Math.max(1, size * .07));
      ctx.shadowBlur = 0;
    }
    const carX = w / 2 + state.carX * w * .31, carY = h * .84, carW = Math.min(100, w * .14), carH = carW * .52;
    ctx.shadowColor = '#9df4d1'; ctx.shadowBlur = 22;
    polygon([[carX - carW * .5, carY + carH], [carX - carW * .38, carY], [carX - carW * .23, carY - carH * .7], [carX + carW * .23, carY - carH * .7], [carX + carW * .38, carY], [carX + carW * .5, carY + carH]], '#88ddc2');
    ctx.shadowBlur = 0;
    polygon([[carX - carW * .22, carY - carH * .57], [carX + carW * .22, carY - carH * .57], [carX + carW * .3, carY - carH * .05], [carX - carW * .3, carY - carH * .05]], '#17383b');
    ctx.fillStyle = '#e987a8'; ctx.fillRect(carX - carW * .4, carY + carH * .6, carW * .24, carH * .12); ctx.fillRect(carX + carW * .16, carY + carH * .6, carW * .24, carH * .12);
    document.querySelector('#distance').innerHTML = `${Math.floor(state.distance)}<small>m</small>`;
    document.querySelector('#speed').innerHTML = `${Math.floor(state.speed)}<small>km/h</small>`;
    document.querySelector('#shield').innerHTML = `${state.shield}<small>/ 3</small>`;
    document.querySelector('#score').textContent = String(state.score);
    document.querySelector('#flash').style.opacity = String(state.hitPulse * .3);
    pause.disabled = !state.running; pause.textContent = state.paused ? 'RESUME' : 'PAUSE';
    if (!state.running && state.elapsed > 0) {
      overlay.hidden = false; document.querySelector('.kicker').textContent = 'UNTIL THE NEXT NIGHT';
      document.querySelector('h1').innerHTML = `One more<br><em>midnight?</em>`;
      document.querySelector('#intro').textContent = `${Math.floor(state.distance)}m driven. ${state.score} points. Your next run starts now.`;
      document.querySelector('#start').innerHTML = 'Drive again <span>↗</span>';
      status.textContent = 'Run complete. Try a different line.';
    }
  }
  document.querySelector('#start').addEventListener('click', () => { simulation.start(); overlay.hidden = true; status.textContent = 'Stay sharp. Dodge the pink barriers.'; previous = performance.now(); render(); });
  document.querySelector('#left').addEventListener('click', () => { simulation.steer(-1); render(); });
  document.querySelector('#right').addEventListener('click', () => { simulation.steer(1); render(); });
  pause.addEventListener('click', () => { simulation.togglePause(); status.textContent = simulation.paused ? 'Night drive paused.' : 'Stay sharp. Dodge the pink barriers.'; render(); });
  scope.addEventListener('keydown', event => { if (event.key === 'ArrowLeft' || event.key === 'a') { event.preventDefault(); simulation.steer(-1); } if (event.key === 'ArrowRight' || event.key === 'd') { event.preventDefault(); simulation.steer(1); } if (event.key === ' ') { event.preventDefault(); simulation.togglePause(); } render(); });
  canvas.addEventListener('pointerdown', event => { const rect = canvas.getBoundingClientRect(); simulation.steer(event.clientX - rect.left < rect.width / 2 ? -1 : 1); render(); });
  scope.addEventListener('resize', () => { resize(); render(); });
  function frame(now) { const dt = Math.min(.05, Math.max(0, (now - previous) / 1000)); previous = now; simulation.step(dt); ambient += simulation.running && !simulation.paused ? dt * simulation.speed / 130 : dt * .15; render(); requestAnimationFrame(frame); }
  scope.__gameTest = Object.freeze({
    snapshot: () => simulation.snapshot(),
    advance: seconds => { const value = simulation.advance(seconds); render(); return value; },
    reset: () => { simulation.reset(); overlay.hidden = false; render(); return simulation.snapshot(); },
    addObstacle: (lane, z) => { simulation.addObstacle(lane, z); render(); return simulation.snapshot(); }
  });
  resize(); render(); requestAnimationFrame(frame);
})(typeof window !== 'undefined' ? window : globalThis);
