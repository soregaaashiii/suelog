import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../../app/views/admin/shops/index.html.erb', import.meta.url), 'utf8');
const start = source.indexOf('      document.querySelectorAll("[data-booking-visibility-form]")');
const script = source.slice(start, source.indexOf('      document.querySelectorAll("[data-tabelog-not-found-form]")', start));
function setup(save) {
  const button = { value: '予約ボタンを非表示', disabled: false };
  const status = { textContent: '', style: {} };
  const hidden = { value: '1' };
  let submit;
  const form = { dataset: {}, querySelector: selector => selector.includes('submit') ? button : selector.includes('name=') ? hidden : status,
    addEventListener: (_, handler) => { submit = handler; } };
  vm.runInNewContext(script, { document: { querySelectorAll: () => [form] }, saveTabelogForm: save });
  return { button, status, hidden, submit: () => submit({ preventDefault() {} }) };
}
test('successful toggle switches to the reverse action only after persistence', async () => {
  let done;
  const ui = setup(() => new Promise(resolve => { done = resolve; }));
  const pending = ui.submit();
  assert.equal(ui.button.disabled, true);
  assert.equal(ui.hidden.value, '1');
  done({ hidden: true });
  await pending;
  assert.equal(ui.hidden.value, '0');
  assert.equal(ui.button.value, '予約ボタンを表示');
  assert.equal(ui.status.textContent, '非表示中');
});
test('failed toggle preserves the intended action and is retryable', async () => {
  const ui = setup(async () => { throw new Error('失敗'); });
  await ui.submit();
  assert.equal(ui.hidden.value, '1');
  assert.equal(ui.button.value, '予約ボタンを非表示');
  assert.equal(ui.button.disabled, false);
  assert.equal(ui.status.textContent, '失敗');
});
