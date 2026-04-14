import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadDenylist, regexRedact, type Denylist } from './guard.ts';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SHIPPED_DENYLIST = path.resolve(__dirname, '../config/denylist.json');

test('regexRedact replaces matches and counts them', () => {
  const denylist: Denylist = {
    patterns: [{ name: 'email', regex: '[\\w.+-]+@[\\w.-]+\\.\\w+' }],
  };
  const result = regexRedact('contact alice@example.com or bob@test.io', denylist);
  assert.equal(result.filtered, 'contact [REDACTED:email] or [REDACTED:email]');
  assert.deepEqual(result.redactions, [{ name: 'email', count: 2 }]);
});

test('regexRedact returns input unchanged when no pattern matches', () => {
  const denylist: Denylist = { patterns: [{ name: 'foo', regex: 'xyz' }] };
  const result = regexRedact('hello world', denylist);
  assert.equal(result.filtered, 'hello world');
  assert.deepEqual(result.redactions, []);
});

test('regexRedact with empty denylist acts as identity', () => {
  const result = regexRedact('keep me intact', { patterns: [] });
  assert.equal(result.filtered, 'keep me intact');
  assert.deepEqual(result.redactions, []);
});

test('regexRedact applies multiple patterns independently', () => {
  const denylist: Denylist = {
    patterns: [
      { name: 'ip', regex: '\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b' },
      { name: 'email', regex: '[\\w.+-]+@[\\w.-]+\\.\\w+' },
    ],
  };
  const result = regexRedact('server 10.0.0.1 owner root@example.com', denylist);
  assert.match(result.filtered, /\[REDACTED:ip\]/);
  assert.match(result.filtered, /\[REDACTED:email\]/);
  assert.equal(result.redactions.length, 2);
});

test('loadDenylist throws for invalid regex patterns', () => {
  const tmpDir = path.join(__dirname, '..', 'node_modules', '.cache-test');
  fs.mkdirSync(tmpDir, { recursive: true });
  const tmpFile = path.join(tmpDir, 'bad-denylist.json');
  fs.writeFileSync(
    tmpFile,
    JSON.stringify({ patterns: [{ name: 'bad', regex: '(?i)bearer\\s+x' }] }),
  );
  assert.throws(() => loadDenylist(tmpFile), /Invalid regex.*bad/);
});

test('shipped denylist.json compiles cleanly and matches samples', () => {
  const denylist = loadDenylist(SHIPPED_DENYLIST);
  assert.ok(denylist.patterns.length > 0, 'should have patterns');

  const sample = [
    'contact foo@example.com',
    'channel C01ABCDEF99',
    'bearer eyJabcdefghijklmnopqrstuvwxyz0123',
    'server 10.0.0.1',
    'AKIAIOSFODNN7EXAMPLE',
  ].join(' ');
  const result = regexRedact(sample, denylist);
  const names = new Set(result.redactions.map((r) => r.name));
  assert.ok(names.has('email'), 'email redacted');
  assert.ok(names.has('slack_channel_id'), 'slack_channel_id redacted');
  assert.ok(names.has('bearer_token'), 'bearer_token redacted');
  assert.ok(names.has('ipv4'), 'ipv4 redacted');
  assert.ok(names.has('aws_access_key'), 'aws_access_key redacted');
});
