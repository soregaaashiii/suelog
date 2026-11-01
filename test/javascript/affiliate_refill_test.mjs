import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../../app/views/admin/shops/index.html.erb', import.meta.url), 'utf8');
const script = source.slice(source.indexOf('      const csrfMeta'), source.indexOf('      function bindTabelogRows()'));
function setup(fetch) {
  const meta = { content: 'old-token' };
  const rows = [{ dataset: { shopRowId: '2' }, unsavedValue: 'https://in-progress.test' }];
  const count = { innerHTML: '' };
  const pagination = { innerHTML: '' };
  const document = {
    querySelector: selector => {
      if (selector.includes('meta')) return meta;
      if (selector.includes('data-shop-rows')) return { appendChild: row => rows.push(row) };
      if (selector.includes('data-shop-row-id')) return rows.find(row => selector.includes(`"${row.dataset.shopRowId}"`));
      return count;
    },
    querySelectorAll: selector => selector.includes('data-shop-row-id') ? rows : selector.includes('pagination') ? [pagination] : [],
    createElement: () => ({ innerHTML: '', content: { querySelectorAll: () => [{ dataset: { shopRowId: '3' } }] } })
  };
  const context = vm.createContext({
    document, window: { location: { href: 'https://suelog.jp/panel_8m4k/shops?status=tabelog_missing&per=2&q=search' } },
    fetch, URL, boxes: [], bindCopyButtons() {}, bindTabelogRows() {}, bindSearchLinks() {}, update() {},
    FormData: class { constructor() { this.values = {}; } set(key, value) { this.values[key] = value; } }
  });
  vm.runInContext(script, context);
  return { meta, rows, count, pagination, save: (form) => vm.runInContext('saveTabelogForm', context)(form), refill: () => vm.runInContext('refillShopRows()', context) };
}
test('stale CSRF is refreshed and retried once with both header and form token', async () => {
  const calls = [];
  const ui = setup(async (url, options) => {
    calls.push(options);
    if (calls.length === 1) return { ok: false, json: async () => ({ code: 'invalid_csrf' }) };
    if (calls.length === 2) return { ok: true, json: async () => ({ csrf_token: 'fresh-token' }) };
    return { ok: true, json: async () => ({ message: 'saved' }) };
  });
  const result = await ui.save({ action: '/save' });
  assert.equal(result.message, 'saved');
  assert.equal(calls.length, 3);
  assert.equal(calls[2].headers['X-CSRF-Token'], 'fresh-token');
  assert.equal(calls[2].body.values.authenticity_token, 'fresh-token');
});
test('refill appends missing rows without overwriting existing input and serializes concurrent refills', async () => {
  let active = 0;
  let peak = 0;
  const ui = setup(async (url) => {
    active++;
    peak = Math.max(peak, active);
    assert.equal(url.searchParams.get('q'), 'search');
    assert.equal(url.searchParams.get('format'), 'json');
    await new Promise(resolve => setTimeout(resolve, 5));
    active--;
    return { ok: true, json: async () => ({ rows_html: '<tr></tr>', total_count: 9, page: 1, total_pages: 5, csrf_token: 'fresh', pagination_html: 'next' }) };
  });
  await Promise.all([ui.refill(), ui.refill()]);
  assert.equal(peak, 1);
  assert.deepEqual(ui.rows.map(row => row.dataset.shopRowId), ['2', '3']);
  assert.equal(ui.rows[0].unsavedValue, 'https://in-progress.test');
  assert.equal(ui.meta.content, 'fresh');
  assert.equal(ui.pagination.innerHTML, 'next');
  assert.match(ui.count.innerHTML, /9/);
});
test('model errors are not retried and non-JSON errors become understandable', async () => {
  let calls = 0;
  const ui = setup(async () => { calls++; return { ok: false, json: async () => ({ error: 'URLが不正です' }) }; });
  await assert.rejects(ui.save({ action: '/save' }), /URLが不正/);
  assert.equal(calls, 1);
  const html = setup(async () => ({ ok: false, json: async () => { throw new Error('HTML'); } }));
  await assert.rejects(html.save({ action: '/save' }), /再読み込み/);
});
