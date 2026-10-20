import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function builder(unknown) {
  const source = readFileSync(new URL('../../app/javascript/controllers/hours_builder_controller.js', import.meta.url), 'utf8')
    .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
    .replace('export default class', 'globalThis.Builder = class');
  const context = vm.createContext({});
  vm.runInContext(source, context);
  const controller = new context.Builder();
  const controls = {
    'span': {textContent:'月'},
    '[data-hours-open]': {checked:true},
    '[data-hours-start1]': {value:'11:00', options:[{value:'11:00'}]},
    '[data-hours-end1]': {value:'21:00', options:[{value:'21:00'}]},
    '[data-smoking-same]': {checked:!unknown},
    '[data-smoking-start]': {value:'', options:[]},
    '[data-smoking-end]': {value:'', options:[]}
  };
  const row = {dataset:{smokingHoursUnknown:String(unknown)}, querySelector:s=>controls[s]};
  controller.element = {querySelectorAll:()=>[row]};
  controller.openingText = {value:''};
  return {controller, controls, row};
}

test('initialization and unrelated changes preserve unknown smoking hours', () => {
  const {controller, controls, row} = builder(true);
  controller.applyLineToRow(row, '月 11:00-21:00');
  assert.equal(controls['[data-smoking-same]'].checked, false);
  assert.equal(controls['[data-smoking-start]'].value, '');
  controller.rebuild();
  assert.equal(controller.openingText.value, '月 11:00-21:00（喫煙可：時間未設定）');
  controller.applyLineToRow(row, controller.openingText.value);
  assert.equal(controls['[data-smoking-same]'].checked, false);
});

test('regular unrestricted schedules retain the existing same-hours default', () => {
  const {controller, controls, row} = builder(false);
  controller.applyLineToRow(row, '月 11:00-21:00');
  assert.equal(controls['[data-smoking-same]'].checked, true);
  controller.rebuild();
  assert.equal(controller.openingText.value, '月 11:00-21:00');
});
