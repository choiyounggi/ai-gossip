import * as fs from 'node:fs';
import * as path from 'node:path';
import type { CachedProfile, RawProfile } from './types.ts';

export function cachePath(cacheDir: string): string {
  return path.join(cacheDir, 'profile.v1.json');
}

export interface SaveCacheInput {
  cacheDir: string;
  internal: RawProfile;
  publicYaml: string;
  draftYaml?: string;
  ttlDays?: number;
  now?: Date;
}

export function saveCache(input: SaveCacheInput): CachedProfile {
  fs.mkdirSync(input.cacheDir, { recursive: true });
  const cached: CachedProfile = {
    schemaVersion: 1,
    createdAt: (input.now ?? new Date()).toISOString(),
    ttlDays: input.ttlDays ?? 7,
    internal: input.internal,
    draftYaml: input.draftYaml,
    publicYaml: input.publicYaml,
  };
  fs.writeFileSync(cachePath(input.cacheDir), JSON.stringify(cached, null, 2));
  return cached;
}

export function loadCache(cacheDir: string): CachedProfile | null {
  try {
    const raw = fs.readFileSync(cachePath(cacheDir), 'utf8');
    return JSON.parse(raw) as CachedProfile;
  } catch {
    return null;
  }
}

export function isExpired(cached: CachedProfile, now: Date = new Date()): boolean {
  const created = new Date(cached.createdAt);
  const ageMs = now.getTime() - created.getTime();
  return ageMs > cached.ttlDays * 24 * 60 * 60 * 1000;
}
