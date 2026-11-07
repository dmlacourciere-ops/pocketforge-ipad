const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NeonRun } = require('../../flutter_app/assets/pocketforge/starter-game.js');

test('Neon Drift starts, steers within lanes, advances distance, and pauses actual simulation', () => {
  const game = new NeonRun();
  assert.equal(game.snapshot().running, false);
  game.start();
  game.steer(-1); game.steer(-1);
  assert.equal(game.snapshot().lane, -1);
  game.advance(.5);
  assert.ok(game.snapshot().distance > 0);
  assert.ok(game.snapshot().carX < -.9);
  game.togglePause();
  const before = game.snapshot();
  game.advance(10); game.steer(1);
  assert.deepEqual(game.snapshot(), before);
  game.togglePause(); game.steer(1); game.advance(.1);
  assert.equal(game.snapshot().lane, 0);
});

test('collision removes one shield exactly once; dodged obstacles score points', () => {
  const game = new NeonRun(); game.start();
  game.addObstacle(0, .905); game.advance(.1);
  assert.equal(game.snapshot().shield, 2);
  game.advance(.2); assert.equal(game.snapshot().shield, 2);
  game.addObstacle(-1, .905); game.advance(.1);
  assert.equal(game.snapshot().passed, 1);
  assert.ok(game.snapshot().score >= game.snapshot().distance + 50);
  game.addObstacle(0, .905); game.advance(.1);
  game.addObstacle(0, .905); game.advance(.1);
  assert.equal(game.snapshot().shield, 0);
  assert.equal(game.snapshot().running, false);
  const finished = game.snapshot(); game.advance(5);
  assert.deepEqual(game.snapshot(), finished);
  game.start(); assert.equal(game.snapshot().shield, 3); assert.equal(game.snapshot().score, 0);
});

test('fixed seed produces reproducible simulation without NaN or oversized time steps', () => {
  const first = new NeonRun(42), second = new NeonRun(42);
  first.start(); second.start();
  first.advance(1); second.advance(1);
  assert.deepEqual(first.snapshot(), second.snapshot());
  first.step(NaN); first.step(-10);
  assert.deepEqual(first.snapshot(), second.snapshot());
  first.step(10000);
  assert.ok(first.snapshot().elapsed < 1.1);
});
