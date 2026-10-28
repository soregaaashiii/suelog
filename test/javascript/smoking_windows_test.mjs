import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
function builder(text = '') {
  const source = readFileSync(new URL('../../app/javascript/controllers/smoking_windows_controller.js', import.meta.url), 'utf8')
    .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
    .replace('export default class', 'globalThis.Builder = class');
  const context = vm.createContext({ Event: class {} });
  vm.runInContext(source, context);
  const c = new context.Builder();
  c.textTarget = {value:text, dispatchEvent(){}};
  c.modeTarget = {value:''}; c.dayTarget = {value:''};
  c.startTarget = {value:'07:00'}; c.finishTarget = {value:'11:00'};
  c.messageTarget = {textContent:''};
  return c;
}
test('adds several windows without losing the first and enables custom mode', () => {
  const c = builder(); c.add();
  c.startTarget.value = '12:30'; c.finishTarget.value = '21:00'; c.add(); c.add();
  assert.equal(c.textTarget.value, '07:00-11:00, 12:30-21:00');
  assert.equal(c.modeTarget.value, 'custom');
});
test('adds to the chosen weekday without changing other days or a ban', () => {
  const c = builder('月 07:00-11:00\n日 喫煙不可');
  c.dayTarget.value = '月'; c.startTarget.value = '12:30'; c.finishTarget.value = '21:00'; c.add();
  assert.equal(c.textTarget.value, '月 07:00-11:00, 12:30-21:00\n日 喫煙不可');
  c.dayTarget.value = '日'; c.add();
  assert.match(c.messageTarget.textContent, /禁煙/);
  assert.match(c.textTarget.value, /日 喫煙不可$/);
  c.dayTarget.value = ''; c.add();
  assert.match(c.messageTarget.textContent, /混在できません/);
});
