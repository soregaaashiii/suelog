import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function harness() {
  const template = readFileSync(new URL('../../app/views/maps/index.html.erb', import.meta.url), 'utf8');
  const source = template.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/<%=.*?%>/g, '[]')
    .replace('window.initMap = initMap;', 'window.initMap = initMap; window.testing = {applyFilters};');
  const nodes = new Map();
  const timers = new Map();
  const requests = [];
  let map;
  let sequence = 0;
  const point = p => ({lat:()=>p.lat, lng:()=>p.lng});
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {value:'',checked:false,style:{},selectedOptions:[],addEventListener(){},textContent:'',innerHTML:''});
    return nodes.get(id);
  };
  class Bounds {
    constructor(sw, ne) {this.sw = sw; this.ne = ne;}
    getSouthWest() {return point(this.sw);}
    getNorthEast() {return point(this.ne);}
  }
  class MapMock {
    constructor(el, options) {map=this; this.center=options.center; this.zoom=15; this.events={};}
    fitBounds(bounds) {this.bounds=bounds;}
    getBounds(){return this.bounds;}
    addListener(name, fn){this.events[name]=fn;}
    getCenter(){return point(this.center);}
    getZoom(){return this.zoom;}
    setCenter(p){this.center=p;}
    setZoom(n){this.zoom=n;}
  }
  const context = {
    window:{location:{search:''},addEventListener(){}},location:{search:'',href:'https://example.test/map'},
    history:{replaceState(){}},document:{getElementById:node,addEventListener(){}},
    navigator:{geolocation:{getCurrentPosition(ok, fail){fail();}}},
    sessionStorage:{getItem(){return null;}}, URL,URLSearchParams,AbortController,console,
    google:{maps:{Map:MapMock,LatLngBounds:Bounds,InfoWindow:class {},SymbolPath:{CIRCLE:'circle'}}},
    setTimeout(fn){const id=++sequence; timers.set(id,fn);return id;},clearTimeout(id){timers.delete(id);},
    fetch(url, options) {return new Promise((resolve,reject)=>{requests.push({url,signal:options.signal,resolve,reject});});}
  };
  vm.runInNewContext(source,context);
  context.window.initMap();
  return {context,nodes,requests,get map(){return map;},
    flush(){const fn=[...timers.values()].at(-1);timers.clear();return fn?.();},
    reply(request,data={shops:[],badges:{},clusters:[],total:0}){request.resolve({ok:true,json:async()=>data});}
  };
}

test('initial view covers an 800m radius and loads only the requested bounds',async()=>{
  const h=harness();
  assert.ok(Math.abs((h.map.bounds.ne.lat-h.map.bounds.sw.lat)*111320-1600)<0.01);
  const pending=h.flush();
  const request=h.requests[0];
  assert.ok(request.url.startsWith('/map.json?south='));
  h.reply(request);await pending;
  assert.match(h.nodes.get('map-status').textContent,/この範囲では/);
  h.map.events.idle();await h.flush();
  assert.equal(h.requests.length,1,'same viewport is reused from the short-lived cache');
});

test('movement cancels old requests and stale results cannot replace the new range',async()=>{
  const h=harness();const first=h.flush();const old=h.requests[0];
  h.map.bounds.ne.lat+=0.02;h.map.bounds.sw.lat+=0.02;
  h.map.events.idle();assert.equal(old.signal.aborted,true);
  const second=h.flush();const latest=h.requests[1];
  h.reply(latest);await second;
  const message=h.nodes.get('map-status').textContent;
  h.reply(old,{shops:[],badges:{},clusters:[],total:999});await first;
  assert.equal(h.nodes.get('map-status').textContent,message);
});

test('failed searches show retry status instead of claiming there are no stores',async()=>{
  const h=harness();const pending=h.flush();h.requests[0].reject(new Error('network'));await pending;
  assert.match(h.nodes.get('map-status').textContent,/再試行/);
});
