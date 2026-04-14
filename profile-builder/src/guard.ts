import * as fs from 'node:fs';
import { execSync } from 'node:child_process';

export interface DenylistPattern {
  name: string;
  regex: string;
}

export interface Denylist {
  patterns: DenylistPattern[];
}

export interface GuardResult {
  filtered: string;
  redactions: { name: string; count: number }[];
}

export function loadDenylist(configPath: string): Denylist {
  const raw = fs.readFileSync(configPath, 'utf8');
  const parsed = JSON.parse(raw) as Denylist;
  if (!Array.isArray(parsed.patterns)) {
    throw new Error(`Invalid denylist at ${configPath}: missing 'patterns' array`);
  }
  for (const p of parsed.patterns) {
    try {
      new RegExp(p.regex, 'gi');
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      throw new Error(
        `Invalid regex in denylist (${configPath}) for pattern "${p.name}": ${reason}`,
      );
    }
  }
  return parsed;
}

export function regexRedact(text: string, denylist: Denylist): GuardResult {
  const counts = new Map<string, number>();
  let filtered = text;
  for (const p of denylist.patterns) {
    const re = new RegExp(p.regex, 'gi');
    filtered = filtered.replace(re, () => {
      counts.set(p.name, (counts.get(p.name) ?? 0) + 1);
      return `[REDACTED:${p.name}]`;
    });
  }
  return {
    filtered,
    redactions: Array.from(counts, ([name, count]) => ({ name, count })),
  };
}

export interface LlmReviewOptions {
  claudeBin?: string;
  timeoutMs?: number;
}

export function llmReview(
  text: string,
  promptPath: string,
  opts: LlmReviewOptions = {},
): string {
  const systemPrompt = fs.readFileSync(promptPath, 'utf8');
  const combined = `${systemPrompt}\n\n[INPUT]\n${text}`;
  const bin = opts.claudeBin ?? 'claude';
  const result = execSync(`${bin} -p`, {
    input: combined,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    timeout: opts.timeoutMs ?? 120_000,
  });
  return result.trim();
}
