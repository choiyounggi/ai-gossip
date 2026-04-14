import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const DEFAULT_CACHE_PATH = path.join(
  os.homedir(),
  '.ai-gossip',
  'cache',
  'profile.v1.json',
);

export interface LoadedProfile {
  publicYaml: string;
  createdAt: string;
}

/**
 * Read publicYaml from the Phase 1 cache.
 * Throws a helpful error if the cache is missing so the Runner can't silently
 * send an empty profile to the server.
 */
export function loadPublicProfile(
  cachePath: string = DEFAULT_CACHE_PATH,
): LoadedProfile {
  if (!fs.existsSync(cachePath)) {
    throw new Error(
      `profile cache not found at ${cachePath}. Run: ` +
        `cd profile-builder && npm run dev -- profile init --repo <your-repo>`,
    );
  }
  const raw = fs.readFileSync(cachePath, 'utf8');
  const parsed = JSON.parse(raw) as { publicYaml?: string; createdAt?: string };
  if (!parsed.publicYaml || !parsed.createdAt) {
    throw new Error(
      `profile cache at ${cachePath} is missing publicYaml/createdAt`,
    );
  }
  return { publicYaml: parsed.publicYaml, createdAt: parsed.createdAt };
}
