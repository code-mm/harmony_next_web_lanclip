// These tests exercise pure address/protocol policy. They do not simulate mobile interactions.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../entry/src/main/ets/model/Protocol.ets', import.meta.url), 'utf8');
const p = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source)).toString('base64')}`);
const marker = { service: 'lanclip', protocolVersion: 1, webPath: '/', apiPath: '/api', webSocketPath: '/ws', authRequired: true,
  capabilities: ['text','link','image','file','websocket','audit'] };
for (const host of ['10.0.0.1','10.255.255.255','172.16.0.1','172.31.255.255','192.168.255.254']) {
  test(`allows RFC1918 ${host}`, () => assert.equal(p.privateIPv4(host), true));
}
for (const host of ['8.8.8.8','127.0.0.1','169.254.1.1','172.15.255.255','172.32.0.0','010.0.0.1','10.0.0.256','10.1.2','localhost','::1','10.0.0.1.evil.test']) {
  test(`rejects non-private or ambiguous ${host}`, () => assert.equal(p.privateIPv4(host), false));
}
test('normalizes only bare local origins', () => {
  assert.equal(p.normalizeOrigin('192.168.1.2:9000/'), 'http://192.168.1.2:9000');
  assert.equal(p.normalizeOrigin('https://10.0.2.2'), 'https://10.0.2.2:443');
  for (const value of ['http://10.0.0.1:0','http://10.0.0.1:65536','http://user:password@10.0.0.1','http://10.0.0.1/path','http://10.0.0.1?token=test','file:///data/a','http://example.test','http://8.8.8.8']) {
    assert.throws(() => p.normalizeOrigin(value));
  }
});
test('actual /23 and /30 containment, not a fabricated /24', () => {
  assert.equal(p.hostAllowed('192.168.11.3', [{address:'192.168.10.9',length:23}]), true);
  assert.equal(p.hostAllowed('192.168.12.3', [{address:'192.168.10.9',length:23}]), false);
  assert.deepEqual(p.scanHosts([{address:'192.168.1.1',length:30}]), ['192.168.1.2']);
});
test('large subnet never traversed and bounded multi-link results', () => {
  assert.deepEqual(p.scanHosts([{address:'10.1.0.2',length:16}]), []);
  assert.equal(p.scanHosts([{address:'192.168.1.1',length:24},{address:'192.168.2.1',length:24}]).length, 256);
  assert.deepEqual(p.scanHosts([{address:'8.8.8.8',length:24}]), []);
});
test('rejects malformed or unbounded port lists', () => {
  assert.deepEqual(p.parsePorts('9000,9001,9000'), [9000,9001]);
  for (const value of ['','0','65536','9.1','80evil','1,2,3,4,5,6,7,8,9']) assert.throws(() => p.parsePorts(value));
});
test('requires complete marker contract and rejects foreign paths', () => {
  assert.equal(p.validMarker(marker), true);
  for (const override of [{service:'other'},{protocolVersion:'1'},{protocolVersion:2},{webPath:'https://evil.test/'},{apiPath:'//evil.test/api'},{webSocketPath:'/other'},{authRequired:'true'},{capabilities:['text']}]) {
    assert.equal(p.validMarker({...marker,...override}), false);
  }
  assert.equal(p.validMarker(null), false);
  assert.equal(p.validMarker(undefined), false);
});
test('legacy identity requires all four page features', () => {
  const html = '<title>局域网剪贴板 | LanClip</title><div id="root"></div><img src="/lanclip-logo.png"><script type="module" src="/static/a.js"></script>';
  assert.equal(p.legacyPage(html), true);
  for (const token of ['局域网剪贴板','id="root"','/lanclip-logo.png','type="module"']) assert.equal(p.legacyPage(html.replace(token,'')), false);
});
test('attachment policy preserves queries and rejects exfiltration/traversal', () => {
  const path = '/api/assets/abc/download?token=test-only&deviceName=A%20B';
  assert.equal(p.safeAssetPath(path), path);
  assert.equal(p.safeAssetPath('/assets/2026/10/24/picture.png'), '/assets/2026/10/24/picture.png');
  for (const path of ['https://evil.test/file','//evil.test/file','/api/health','/api/assets/%2e%2e/download','/assets/../config','/assets/%2e%2e/config','/assets/a\\b','/assets/a#x']) assert.throws(() => p.safeAssetPath(path));
});
test('filesystem names are bounded and sanitized', () => {
  assert.equal(p.safeFilename('../test\u0000.png'), '.._test_.png');
  assert.equal(p.safeFilename(''), 'LanClip-file');
  assert.equal(p.safeFilename('a'.repeat(500)).length, 180);
});
