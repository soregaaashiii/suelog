import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const template = readFileSync(new URL('../../app/views/admin/shops/index.html.erb', import.meta.url), 'utf8');
const start = template.indexOf('      function focusTabelogInput(form)');
const script = template.slice(start, template.indexOf('\n      update();', start));

function setup(fetch) {
  const total = { textContent: '10' };
  const notice = { hidden: true, textContent: '' };
  const windowEvents = {};
  const documentEvents = {};
  const storage = new Map();
  const document = { activeElement: null, visibilityState: 'visible', body: {},
    addEventListener: (event, handler) => { documentEvents[event] = handler; }
  };
  const forms = [];
  const links = [];
  const rows = [1, 2].map(id => {
    const status = { textContent: '', style: {} };
    const button = { disabled: false };
    const inputEvents = {};
    const input = { addEventListener: (event, handler) => { inputEvents[event] = handler; }, value: 'https://tabelog.com/test/', readOnly: false, selections: 0,
      focus() { document.activeElement = this; }, select() { this.selections++; }
    };
    const checkbox = { checked: true };
    const row = { removed: false, querySelector: selector => selector.includes('search-shop') ? link : checkbox, remove() { this.removed = true; } };
    let submit;
    const form = {
      dataset: { shopId: String(id) }, action: `/panel_8m4k/shops/${id}`,
      querySelector: selector => selector.includes('status') ? status : selector.includes('submit') ? button : input,
      closest: () => row, contains: element => element === input || element === button,
      addEventListener: (event, handler) => { submit = handler; }
    };
    const link = { dataset: { tabelogSearchShopId: String(id) },
      addEventListener(event, handler) { this.click = handler; }
    };
    forms.push(form); links.push(link);
    return { status, button, input, inputEvents, row, checkbox, submit: () => submit({ preventDefault() {} }) };
  });
  document.querySelectorAll = selector => selector.includes('search-shop') ? links : forms.filter((_, i) => !rows[i].row.removed);
  document.querySelector = selector => {
    if (selector.includes('data-shop-total')) return total;
    if (selector.includes('data-url-update-notice')) return notice;
    const id = selector.match(/data-shop-id="(\d+)"/);
    return id ? forms.find(form => form.dataset.shopId === id[1]) : forms[0];
  };
  vm.runInNewContext(script, {
    document, fetch, boxes: rows.map(row => row.checkbox), update: () => {},
    window: { addEventListener: (event, handler) => { windowEvents[event] = handler; } },
    sessionStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
    FormData: class { constructor(value) { assert.ok(forms.includes(value)); } }
  });
  return { ...rows[0], next: rows[1], total, notice, document, windowEvents, documentEvents, links };
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
  ui.input.focus();
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
  assert.equal(ui.document.activeElement, ui.next.input);
  assert.equal(ui.next.input.selections, 1);
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

test('Google search targets that shop, restores it on return, and does not focus the first row on load', () => {
  const ui = setup(async () => { throw new Error('must not save on focus'); });
  assert.equal(ui.document.activeElement, null);
  ui.links[1].click();
  assert.equal(ui.document.activeElement, ui.next.input);
  ui.document.activeElement = ui.document.body;
  ui.document.visibilityState = 'hidden';
  ui.documentEvents.visibilitychange();
  assert.equal(ui.document.activeElement, ui.document.body);
  ui.document.visibilityState = 'visible';
  ui.windowEvents.focus();
  assert.equal(ui.document.activeElement, ui.next.input);
  ui.document.activeElement = ui.input;
  ui.windowEvents.focus();
  assert.equal(ui.document.activeElement, ui.input);
});

test('empty Enter opens that row search without saving, while nonempty Enter and IME remain unchanged', () => {
  let requests = 0;
  const ui = setup(async () => { requests++; });
  let prevented = 0;
  ui.next.input.value = '  ';
  ui.next.inputEvents.keydown({ key: 'Enter', isComposing: false, preventDefault() { prevented++; } });
  assert.equal(prevented, 1);
  assert.equal(requests, 0);
  assert.equal(ui.document.activeElement, ui.next.input);
  ui.next.input.value = 'https://tabelog.com/test/';
  ui.next.inputEvents.keydown({ key: 'Enter', isComposing: false, preventDefault() { prevented++; } });
  ui.next.input.value = '';
  ui.next.inputEvents.keydown({ key: 'Enter', isComposing: true, preventDefault() { prevented++; } });
  assert.equal(prevented, 1);
});
