import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../../app/views/admin/shops/index.html.erb', import.meta.url), 'utf8');
const start = source.indexOf('      document.querySelectorAll("[data-tabelog-not-found-form]")');
const script = source.slice(start, source.indexOf('      }\n      bindTabelogRows();', start));
function setup(fetch, confirmed = true, provider) {
  const button = { textContent: '食べログなし', disabled: false };
  const notice = { hidden: true, style: {} };
  const total = { textContent: '4' };
  const checkbox = { checked: true };
  const row = { removed: false, querySelector: () => checkbox, remove() { this.removed = true; } };
  let handler;
  const form = { dataset: { bookingProvider: provider }, action: '/not-found', querySelector: () => button, closest: () => row,
    addEventListener: (_, fn) => { handler = fn; } };
  vm.runInNewContext(script, {
    document: { querySelectorAll: () => [form], querySelector: selector => selector.includes('total') ? total : notice },
    saveTabelogForm: async form => {
      const response = await fetch(form.action, { headers: { Accept: 'application/json' } });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      return result;
    }, refillShopRows: async () => {}, window: { confirm: () => confirmed }, boxes: [checkbox], update() {}, fetch,
    FormData: class { constructor(target) { assert.equal(target, form); } }
  });
  return { button, notice, total, row, checkbox, submit: () => handler({ preventDefault() {} }) };
}
test('not found waits for success, blocks duplicate requests and removes the completed row', async () => {
  let finish;
  let requests = 0;
  const ui = setup((url, options) => {
    requests++;
    assert.equal(options.headers.Accept, 'application/json');
    return new Promise(resolve => { finish = resolve; });
  });
  const pending = ui.submit();
  assert.equal(ui.button.disabled, true);
  assert.equal(ui.row.removed, false);
  await ui.submit();
  assert.equal(requests, 1);
  finish({ ok: true, json: async () => ({ shop_name: '店舗' }) });
  await pending;
  assert.equal(ui.row.removed, true);
  assert.equal(ui.checkbox.checked, false);
  assert.equal(ui.total.textContent, '3');
  assert.match(ui.notice.textContent, /食べログなしとして登録/);
});
test('cancellation sends nothing, and failure keeps the row available for retry', async () => {
  const cancelled = setup(() => { throw new Error('must not submit'); }, false);
  await cancelled.submit();
  assert.equal(cancelled.row.removed, false);
  let requests = 0;
  const ui = setup(async () => { requests++; return { ok: false, json: async () => ({ error: '失敗' }) }; });
  await ui.submit();
  assert.equal(ui.row.removed, false);
  assert.equal(ui.total.textContent, '4');
  assert.equal(ui.notice.textContent, '失敗');
  assert.equal(ui.button.disabled, false);
  await ui.submit();
  assert.equal(requests, 2);
});

test('Hot Pepper not found uses its provider name in the completion message', async () => {
  const ui = setup(async () => ({ ok: true, json: async () => ({ shop_name: '店舗' }) }), true, 'ホットペッパー');
  await ui.submit();
  assert.match(ui.notice.textContent, /ホットペッパーなし/);
  assert.equal(ui.row.removed, true);
});
