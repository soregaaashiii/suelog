import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

test('viewport refresh keeps the selected marker and uses updated shop data', () => {
  const source = fs.readFileSync('app/views/maps/index.html.erb', 'utf8');
  const code = source.slice(source.indexOf('function renderMarkers(shops)'), source.indexOf('function fitMarkersToBounds'));
  const removed = [];
  class Marker {
    constructor(options) { this.options = options; }
    addListener(name, fn) { this[name] = fn; }
    setPosition() {}
    setIcon() {}
    setMap(value) { if (value === null) removed.push(this); }
  }
  const context = { markers: [], map: {}, google: { maps: { Marker } }, markerIconFor: () => ({}), updateVisibleCount() {}, buildInfoHtml: shop => shop.name, infoWindow: { setContent(value) { this.content = value; }, open(options) { this.options = options; } } };
  vm.createContext(context); vm.runInContext(code, context);
  context.renderMarkers([{ id: 1, name: '店舗A', lat: 1, lng: 1 }]);
  const selected = context.markers[0]; selected.click();
  context.renderMarkers([{ id: 1, name: '店舗A更新', lat: 1, lng: 1 }, { id: 2, name: '店舗B', lat: 2, lng: 2 }]);
  assert.equal(context.markers[0], selected);
  assert.equal(context.infoWindow.options.anchor, selected);
  assert.equal(context.infoWindow.options.shouldFocus, false);
  assert.equal(removed.length, 0);
  selected.click(); assert.equal(context.infoWindow.content, '店舗A更新');
  context.renderMarkers([{ id: 2, name: '店舗B', lat: 2, lng: 2 }]);
  assert.deepEqual(removed, [selected]);
  assert.match(source, /idle", \(\) => applyFilters\(\{ preserveMarkers: true \}\)/);
});
