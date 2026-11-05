import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../../app/javascript/controllers/csv_registration_controller.js', import.meta.url), 'utf8').replace(/^import .*\n/, '').replace('export default class', 'globalThis.CsvController = class');
function setup(responses) {
  const calls = [], scrolls = [];
  const controls = [{ disabled: false }, { disabled: true }];
  const card = { dataset: {}, querySelectorAll: () => controls, removed: false, remove() { this.removed = true; } };
  const status = { textContent: '', hidden: true };
  const context = vm.createContext({ setTimeout, clearTimeout, Controller: class {}, document: { querySelector: () => ({ content: 'csrf' }) }, window: { scrollY: 420, scrollTo: value => scrolls.push(value.top), location: { href: 'https://example.test/csv/2?page=2' } },
    FormData: class { constructor() { this.data = {}; } set(k, v) { this.data[k] = v; } },
    fetch: async (url, options) => { calls.push({ url, options }); const response = responses.shift(); if (response instanceof Error) throw response; return response; },
    DOMParser: class { parseFromString() { return { querySelector: () => null }; } }
  });
  vm.runInContext(source, context);
  const controller = new context.CsvController();
  controller.element = { querySelector: selector => selector.includes("status") ? status : null, querySelectorAll: () => [] };
  let prevented = false;
  const event = { submitter: { name: 'decision', value: 'register' }, preventDefault() { prevented = true; }, target: { action: '/review', closest: () => card } };
  return { controller, event, card, status, calls, controls, scrolls, prevented: () => prevented };
}
const json = (success = true, message = '登録しました') => ({ ok: success, headers: { get: () => 'application/json' }, json: async () => ({ success, message }) });
test('registration submits JSON, removes only its card, preserves scroll and does not retry after refill failure', async () => {
  const ui = setup([json(), new Error('offline')]);
  await ui.controller.submit(ui.event);
  assert.ok(ui.prevented()); assert.ok(ui.card.removed);
  assert.equal(ui.calls.length, 2);
  assert.equal(ui.calls[0].options.body.data.decision, 'register');
  assert.equal(ui.calls[0].options.headers.Accept, 'application/json');
  assert.equal(ui.calls[1].options.headers.Accept, 'text/html');
  assert.deepEqual(ui.scrolls, [420]);
  assert.match(ui.status.textContent, /登録しました.*更新に失敗/);
  assert.equal(ui.controls[0].disabled, false); assert.equal(ui.controls[1].disabled, true);
});
test('conflict leaves the card visible and re-enables controls without navigation', async () => {
  const ui = setup([json(false, '店舗データが更新されています')]);
  await ui.controller.submit(ui.event);
  assert.equal(ui.card.removed, false); assert.equal(ui.calls.length, 1);
  assert.match(ui.status.textContent, /更新/); assert.equal(ui.controller.saving, false);
});
test('duplicate submission while saving does not send another request', async () => {
  const ui = setup([]); ui.controller.saving = true;
  await ui.controller.submit(ui.event);
  assert.ok(ui.prevented()); assert.equal(ui.calls.length, 0);
});
test('unrelated forms keep their normal submission', async () => {
  const ui = setup([]); ui.event.submitter.value = 'hold';
  await ui.controller.submit(ui.event);
  assert.equal(ui.prevented(), false); assert.equal(ui.calls.length, 0);
});
test('refill replaces counts and appends new cards without replacing remaining edits or navigating', async () => {
  const ui = setup([json(), { ok: true, text: async () => '<html></html>' }]);
  const existing = { dataset: { targetShop: '2' }, unsavedInput: 'keep me', after(node) { appended.push(node); } };
  const appended = [], replaced = [];
  const next = { dataset: { targetShop: '3' } };
  ui.controller.element = {
    querySelector(selector) {
      if (selector.includes('status')) return ui.status;
      if (selector.includes('shortcut')) return null;
      if (selector === '[data-target-shop="2"]') return existing;
      if (selector === '[data-target-shop="3"]') return null;
      return { replaceWith: node => replaced.push(node) };
    },
    querySelectorAll: selector => selector.includes('button') ? [] : [existing]
  };
  // The HTML parser stub returns a normal refreshed page; existing cards must be kept.
  const parsed = { querySelector: () => ({}), querySelectorAll: () => [existing, next] };
  const sourceWithParser = source.replace('new DOMParser().parseFromString(await fresh.text(), "text/html")', 'globalThis.refreshedPage');
  const context = vm.createContext({ setTimeout, clearTimeout, Controller: class {}, refreshedPage: parsed, document: { querySelector: () => ({ content: 'csrf' }) }, window: { scrollY: 420, scrollTo: value => ui.scrolls.push(value.top), location: { href: '/csv/2' } }, FormData: class { set() {} }, fetch: async () => ui.calls.length++ === 0 ? json() : { ok: true } });
  vm.runInContext(sourceWithParser, context);
  const controller = new context.CsvController(); controller.element = ui.controller.element;
  await controller.submit(ui.event);
  assert.deepEqual(appended, [next]); assert.equal(replaced.length, 3);
  assert.equal(existing.unsavedInput, 'keep me');
  assert.deepEqual(ui.scrolls, [420, 420]);
  assert.equal(ui.status.textContent, '登録しました');
});

test('exclude and restore use inline submission without navigation', async () => {
  for (const decision of ['exclude', 'restore']) {
    const ui = setup([json(), new Error('offline')]);
    ui.event.submitter.value = decision;
    await ui.controller.submit(ui.event);
    assert.ok(ui.prevented()); assert.ok(ui.card.removed);
    assert.equal(ui.calls[0].options.body.data.decision, decision);
  }
});

function shortcutSetup() {
  const ui = setup([]);
  let submitted = 0;
  const button = { disabled: false, form: { querySelector: () => null, requestSubmit: value => { assert.equal(value, button); submitted++; } } };
  ui.controller.element = { querySelector: selector => selector.includes('shortcut-button') ? {} : button, querySelectorAll: () => [button] };
  const event = { type: 'keydown', key: 'Enter', target: { closest: () => null }, preventDefault() { this.prevented = true; } };
  return { ...ui, event, button, submitted: () => submitted };
}
test('Enter registers the first available candidate without moving the cursor', () => {
  const ui = shortcutSetup(); ui.controller.registerFirst(ui.event);
  assert.equal(ui.submitted(), 1); assert.ok(ui.event.prevented);
});
test('Enter ignores editing, IME, repeats, modifiers and concurrent registration', () => {
  for (const attributes of [{ isComposing: true }, { repeat: true }, { ctrlKey: true }, { metaKey: true }, { altKey: true }, { shiftKey: true }, { key: 'Escape' }, { defaultPrevented: true }]) {
    const ui = shortcutSetup(); Object.assign(ui.event, attributes);
    ui.controller.registerFirst(ui.event); assert.equal(ui.submitted(), 0);
  }
  const editing = shortcutSetup(); editing.event.target.closest = () => ({});
  editing.controller.registerFirst(editing.event); assert.equal(editing.submitted(), 0);
  const busy = shortcutSetup(); busy.controller.saving = true;
  busy.controller.registerFirst(busy.event); assert.equal(busy.submitted(), 0);
});
test('fixed shortcut button uses the same first candidate submission', () => {
  const ui = shortcutSetup(); ui.event.type = 'click';
  ui.controller.registerFirst(ui.event); assert.equal(ui.submitted(), 1);
});

test('Enter registers the actual first candidate including an existing URL replacement', () => {
  const ui = shortcutSetup(); const checkbox = { checked: false }; let firstSubmitted = false;
  const first = { disabled: true, form: { querySelector: () => checkbox, requestSubmit: button => { assert.equal(button, first); firstSubmitted = true; } } };
  ui.controller.element.querySelectorAll = () => [first, ui.button];
  ui.controller.registerFirst(ui.event);
  assert.equal(checkbox.checked, true); assert.equal(first.disabled, false);
  assert.equal(firstSubmitted, true); assert.equal(ui.submitted(), 0);
});
test('replacement buttons stay disabled until their explicit checkbox is checked', () => {
  const ui = shortcutSetup(); const checkbox = { checked: false };
  const button = { disabled: false, form: { querySelector: () => checkbox }, closest: () => ({ dataset: {} }) };
  ui.controller.element.querySelectorAll = () => [button];
  ui.controller.element.querySelector = () => null;
  ui.controller.refreshShortcut(); assert.equal(button.disabled, true);
  checkbox.checked = true; ui.controller.refreshShortcut(); assert.equal(button.disabled, false);
});

test('saving releases the next Enter before a slow list refill completes', async () => {
  const ui = setup([json()]);
  let finishRefill;
  ui.controller.refill = () => new Promise(resolve => { finishRefill = resolve; });
  const pending = ui.controller.submit(ui.event);
  while (!finishRefill) await Promise.resolve();
  assert.equal(ui.controller.saving, false);
  assert.equal(ui.card.removed, true);
  assert.equal(ui.controls[0].disabled, false);
  finishRefill(); await pending;
});
test('full work pages do not fetch the entire list after every registration', async () => {
  const ui = setup([json()]);
  ui.controller.element.querySelectorAll = selector => selector === '[data-target-shop]' ? Array(40).fill({}) : [];
  await ui.controller.submit(ui.event);
  assert.equal(ui.calls.length, 1);
  assert.equal(ui.controller.saving, false);
});
test('a stale refill cannot reinsert a completed shop or overwrite updated counts', async () => {
  const ui = setup([]);
  const candidate = { dataset: { targetShop: '9' } };
  const parsed = { querySelector: () => ({}), querySelectorAll: () => [candidate] };
  let finishFetch, replacements = 0, inserted = 0;
  const context = vm.createContext({ setTimeout, clearTimeout, Controller: class {}, refreshedPage: parsed, window: { scrollY: 123, scrollTo() {}, location: { href: '/csv/2' } }, fetch: () => new Promise(resolve => { finishFetch = resolve; }) });
  vm.runInContext(source.replace('new DOMParser().parseFromString(await fresh.text(), "text/html")', 'globalThis.refreshedPage'), context);
  const controller = new context.CsvController();
  controller.revision = 1; controller.removedShopIds = new Set(['9']);
  controller.element = { querySelector: () => ({ replaceWith() { replacements++; }, after() { inserted++; } }), querySelectorAll: () => Array(40).fill({}) };
  controller.refreshShortcut = () => {};
  const refill = controller.refill();
  controller.revision = 2;
  finishFetch({ ok: true }); await refill;
  assert.equal(replacements, 0); assert.equal(inserted, 0);
});

test('held Enter sends one registration at a time and releasing it cancels the next', () => {
  const timers = new Map(); let nextTimer = 0, submitted = 0, controller;
  const button = { disabled: false, form: { querySelector: () => null, requestSubmit() { assert.equal(!!controller.saving, false); controller.saving = true; submitted++; } } };
  const context = vm.createContext({ Controller: class {}, document: { visibilityState: 'visible' }, setTimeout(fn) { timers.set(++nextTimer, fn); return nextTimer; }, clearTimeout(id) { timers.delete(id); } });
  vm.runInContext(source, context); controller = new context.CsvController();
  controller.element = { querySelector: () => ({}), querySelectorAll: () => [button] };
  const event = { type: 'keydown', key: 'Enter', target: { closest: () => null }, preventDefault() {} };
  controller.registerFirst(event); assert.equal(submitted, 1);
  controller.scheduleHeldEnter(); assert.equal(timers.size, 0);
  controller.saving = false; controller.scheduleHeldEnter(); assert.equal(timers.size, 1);
  const callback = [...timers.values()][0]; timers.clear(); callback();
  assert.equal(submitted, 2); assert.equal(controller.saving, true);
  controller.saving = false; controller.scheduleHeldEnter();
  controller.stopHeldEnter({ type: 'keyup', key: 'Enter' });
  assert.equal(timers.size, 0); assert.equal(controller.enterHeld, false);
});
test('registration errors stop held Enter and blur or editing stop it too', async () => {
  const ui = setup([json(false, '競合')]); ui.controller.enterHeld = true;
  await ui.controller.submit(ui.event); assert.equal(ui.controller.enterHeld, false);
  ui.controller.enterHeld = true; ui.controller.stopHeldEnter({ type: 'blur' }); assert.equal(ui.controller.enterHeld, false);
  ui.controller.enterHeld = true; ui.controller.stopOnEditing({ target: { closest: () => ({}) } }); assert.equal(ui.controller.enterHeld, false);
  ui.controller.enterHeld = true; ui.controller.disconnect(); assert.equal(ui.controller.enterHeld, false);
});

test('URL ownership errors move the card away and allow held registration to continue', async () => {
  const ui = setup([{ ok: false, headers: { get: () => 'application/json' }, json: async () => ({ success: false, remove_from_list: true, destination: 'conflict', message: '競合一覧へ移しました' }) }, new Error('offline')]);
  ui.controller.element.querySelectorAll = selector => selector === '[data-target-shop]' ? Array(40).fill({}) : [];
  ui.controller.enterHeld = true;
  await ui.controller.submit(ui.event);
  assert.equal(ui.card.removed, true);
  assert.equal(ui.controller.enterHeld, true);
  assert.equal(ui.controller.saving, false);
  assert.match(ui.status.textContent, /競合一覧/);
});
