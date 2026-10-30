import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const template = readFileSync(new URL('../../app/views/admin/shops/index.html.erb', import.meta.url), 'utf8');
const start = template.indexOf('      document.querySelectorAll("[data-inline-tabelog-form]")');
const script = template.slice(start, template.indexOf('\n      update();', start));

function setup(fetch) {
  const status = { textContent: '', style: {} };
  const button = { disabled: false };
  const input = { value: 'https://tabelog.com/test/', readOnly: false };
  const checkbox = { checked: true };
  const total = { textContent: '10' };
  const notice = { hidden: true, textContent: '' };
  const row = { removed: false, querySelector: () => checkbox, remove() { this.removed = true; } };
  let submit;
  const form = {
    dataset: {}, action: '/panel_8m4k/shops/1',
    querySelector: selector => selector.includes('status') ? status : selector.includes('submit') ? button : input,
    closest: () => row,
    addEventListener: (event, handler) => { submit = handler; }
  };
  vm.runInNewContext(script, {
    document: { querySelectorAll: () => [form], querySelector: selector => selector.includes('total') ? total : notice }, fetch,
    boxes: [checkbox], update: () => {},
    FormData: class { constructor(value) { assert.equal(value, form); } }
  });
  return { status, button, input, row, checkbox, total, notice, submit: () => submit({ preventDefault() {} }) };
}

test('Enter saves in place once, waits for persistence, and restores input', async () => {
  let resolve;
  let requests = 0;
  const ui = setup((url, options) => {
    requests++;
    assert.equal(url, '/panel_8m4k/shops/1');
    assert.equal(options.headers.Accept, 'application/json');
    return new Promise(done => { resolve = done; });
  });
  const pending = ui.submit();
  assert.equal(ui.status.textContent, '保存中…');
  assert.equal(ui.button.disabled, true);
  await ui.submit();
  assert.equal(requests, 1);
  resolve({ ok: true, json: async () => ({ message: '更新しました', url: 'https://tabelog.com/test/' }) });
  await pending;
  assert.equal(ui.row.removed, true);
  assert.equal(ui.checkbox.checked, false);
  assert.equal(ui.total.textContent, '9');
  assert.equal(ui.notice.hidden, false);
  assert.match(ui.notice.textContent, /設定済みへ移動/);
  assert.equal(ui.button.disabled, false);
  assert.equal(ui.input.readOnly, false);
});

test('failed saves preserve URL, show an error, and allow retry', async () => {
  let attempts = 0;
  const ui = setup(async () => {
    attempts++;
    return { ok: false, json: async () => ({ error: '保存できませんでした' }) };
  });
  await ui.submit();
  assert.equal(ui.status.textContent, '保存できませんでした');
  assert.equal(ui.input.value, 'https://tabelog.com/test/');
  assert.equal(ui.row.removed, false);
  assert.equal(ui.total.textContent, '10');
  assert.equal(ui.button.disabled, false);
  await ui.submit();
  assert.equal(attempts, 2);
});
