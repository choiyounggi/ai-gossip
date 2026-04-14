import * as fs from 'node:fs';
import { execSync } from 'node:child_process';
import type { RawProfile } from './types.ts';

export interface AbstractOptions {
  claudeBin?: string;
  timeoutMs?: number;
}

export function generateDraftProfile(
  raw: RawProfile,
  promptPath: string,
  opts: AbstractOptions = {},
): string {
  const systemPrompt = fs.readFileSync(promptPath, 'utf8');
  const payload = JSON.stringify(raw, null, 2);
  const input = `${systemPrompt}\n\n[RAW_PROFILE]\n\`\`\`json\n${payload}\n\`\`\``;

  const bin = opts.claudeBin ?? 'claude';
  const result = execSync(`${bin} -p`, {
    input,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    timeout: opts.timeoutMs ?? 180_000,
  });
  return result.trim();
}
