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
  const context = vm.createContext({ Controller: class {}, document: { querySelector: () => ({ content: 'csrf' }) }, window: { scrollY: 420, scrollTo: value => scrolls.push(value.top), location: { href: 'https://example.test/csv/2?page=2' } },
    FormData: class { constructor() { this.data = {}; } set(k, v) { this.data[k] = v; } },
    fetch: async (url, options) => { calls.push({ url, options }); const response = responses.shift(); if (response instanceof Error) throw response; return response; },
    DOMParser: class { parseFromString() { return { querySelector: () => null }; } }
  });
  vm.runInContext(source, context);
  const controller = new context.CsvController();
  controller.element = { querySelector: selector => selector.includes("status") ? status : null };
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
    querySelectorAll: () => [existing]
  };
  // The HTML parser stub returns a normal refreshed page; existing cards must be kept.
  const parsed = { querySelector: () => ({}), querySelectorAll: () => [existing, next] };
  const sourceWithParser = source.replace('new DOMParser().parseFromString(await fresh.text(), "text/html")', 'globalThis.refreshedPage');
  const context = vm.createContext({ Controller: class {}, refreshedPage: parsed, document: { querySelector: () => ({ content: 'csrf' }) }, window: { scrollY: 420, scrollTo: value => ui.scrolls.push(value.top), location: { href: '/csv/2' } }, FormData: class { set() {} }, fetch: async () => ui.calls.length++ === 0 ? json() : { ok: true } });
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
  const button = { disabled: false, form: { requestSubmit: value => { assert.equal(value, button); submitted++; } } };
  ui.controller.element = { querySelector: selector => selector.includes('shortcut-button') ? {} : button };
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
