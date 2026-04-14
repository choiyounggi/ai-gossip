import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isExpired } from './cache.ts';
import type { CachedProfile } from './types.ts';

function fixture(createdAt: string, ttlDays: number): CachedProfile {
  return {
    schemaVersion: 1,
    createdAt,
    ttlDays,
    internal: {
      schemaVersion: 1,
      collectedAt: createdAt,
      ownerHints: { systemUser: 'test' },
      instructions: { referenceFiles: [] },
      settings: { hookKeys: [] },
      tools: { skillNames: [], pluginNames: [] },
      memory: [],
      sessionSamples: [],
      auditSummary: [],
      gitActivity: [],
    },
    publicYaml: '',
  };
}

test('isExpired returns true after TTL passes', () => {
  const cached = fixture('2026-04-01T00:00:00Z', 7);
  const now = new Date('2026-04-09T00:00:00Z'); // 8 days later
  assert.equal(isExpired(cached, now), true);
});

test('isExpired returns false within TTL', () => {
  const cached = fixture('2026-04-01T00:00:00Z', 7);
  const now = new Date('2026-04-05T12:00:00Z'); // 4.5 days later
  assert.equal(isExpired(cached, now), false);
});

test('isExpired boundary: exactly at TTL is NOT expired', () => {
  const cached = fixture('2026-04-01T00:00:00Z', 7);
  const now = new Date('2026-04-08T00:00:00Z'); // exactly 7 days
  assert.equal(isExpired(cached, now), false);
});

test('isExpired boundary: 1ms past TTL is expired', () => {
  const cached = fixture('2026-04-01T00:00:00Z', 7);
  const now = new Date('2026-04-08T00:00:00.001Z');
  assert.equal(isExpired(cached, now), true);
});
