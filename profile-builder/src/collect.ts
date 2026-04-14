import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { execSync } from 'node:child_process';
import type {
  RawProfile,
  SessionSample,
  GitActivity,
  ToolCount,
} from './types.ts';

const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, '.claude');
const TWO_WEEKS_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_SESSIONS = 30;
const FIRST_MSG_MAX_CHARS = 500;

export interface CollectOptions {
  whitelistedRepos: string[];
  now?: Date;
}

export function collect(opts: CollectOptions): RawProfile {
  const now = opts.now ?? new Date();
  const cutoff = new Date(now.getTime() - TWO_WEEKS_MS);

  return {
    schemaVersion: 1,
    collectedAt: now.toISOString(),
    ownerHints: collectOwnerHints(),
    instructions: collectInstructions(),
    settings: collectSettings(),
    tools: collectTools(),
    memory: collectMemory(),
    sessionSamples: collectSessionSamples(cutoff),
    auditSummary: collectAuditSummary(cutoff),
    gitActivity: collectGitActivity(opts.whitelistedRepos, cutoff),
  };
}

function collectOwnerHints(): RawProfile['ownerHints'] {
  return {
    gitUserName: tryExec('git config --global user.name'),
    gitUserEmail: tryExec('git config --global user.email'),
    systemUser: os.userInfo().username,
  };
}

function collectInstructions(): RawProfile['instructions'] {
  return {
    claudeMd: readIfExists(path.join(CLAUDE_DIR, 'CLAUDE.md')),
    instructionsMd: readIfExists(path.join(CLAUDE_DIR, 'instructions.md')),
    referenceFiles: listFiles(path.join(CLAUDE_DIR, 'references'), '.md'),
  };
}

function collectSettings(): RawProfile['settings'] {
  const raw = readIfExists(path.join(CLAUDE_DIR, 'settings.json'));
  if (!raw) return { hookKeys: [] };
  try {
    const parsed = JSON.parse(raw) as { hooks?: Record<string, unknown> };
    return { hookKeys: Object.keys(parsed.hooks ?? {}) };
  } catch {
    return { hookKeys: [] };
  }
}

function collectTools(): RawProfile['tools'] {
  return {
    skillNames: listDirs(path.join(CLAUDE_DIR, 'skills')),
    pluginNames: listDirs(path.join(CLAUDE_DIR, 'plugins')),
  };
}

function collectMemory(): string[] {
  const projectsDir = path.join(CLAUDE_DIR, 'projects');
  if (!fs.existsSync(projectsDir)) return [];
  const results: string[] = [];
  for (const proj of safeReaddir(projectsDir)) {
    const memPath = path.join(projectsDir, proj, 'memory', 'MEMORY.md');
    const content = readIfExists(memPath);
    if (content) results.push(`# ${proj}\n${content}`);
  }
  return results;
}

function collectSessionSamples(cutoff: Date): SessionSample[] {
  const projectsDir = path.join(CLAUDE_DIR, 'projects');
  if (!fs.existsSync(projectsDir)) return [];
  const samples: SessionSample[] = [];

  for (const proj of safeReaddir(projectsDir)) {
    const projDir = path.join(projectsDir, proj);
    let stat: fs.Stats;
    try {
      stat = fs.statSync(projDir);
    } catch {
      continue;
    }
    if (!stat.isDirectory()) continue;

    for (const file of safeReaddir(projDir)) {
      if (!file.endsWith('.jsonl')) continue;
      const full = path.join(projDir, file);
      let fstat: fs.Stats;
      try {
        fstat = fs.statSync(full);
      } catch {
        continue;
      }
      if (fstat.mtime < cutoff) continue;
      const summary = summarizeSession(full, fstat.mtime);
      if (summary) samples.push(summary);
    }
  }

  samples.sort((a, b) => b.mtime.localeCompare(a.mtime));
  return samples.slice(0, MAX_SESSIONS);
}

function summarizeSession(file: string, mtime: Date): SessionSample | null {
  try {
    const content = fs.readFileSync(file, 'utf8');
    const lines = content.split('\n').filter((l) => l.trim().length > 0);
    const firstUserMessage = extractFirstUserMessage(lines);
    return {
      file: path.basename(file),
      mtime: mtime.toISOString(),
      firstUserMessage,
      messageCount: lines.length,
    };
  } catch {
    return null;
  }
}

function extractFirstUserMessage(lines: string[]): string | undefined {
  for (const line of lines) {
    try {
      const parsed = JSON.parse(line) as Record<string, unknown>;
      const role = (parsed.type ?? parsed.role) as string | undefined;
      if (role !== 'user') continue;
      const content =
        (parsed.content as unknown) ??
        ((parsed.message as Record<string, unknown> | undefined)?.content as unknown);
      const text = normalizeContent(content);
      if (text) return text.slice(0, FIRST_MSG_MAX_CHARS);
    } catch {
      // skip bad lines
    }
  }
  return undefined;
}

function normalizeContent(content: unknown): string | undefined {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    const parts = content
      .map((c: unknown) => {
        if (typeof c === 'string') return c;
        if (c && typeof c === 'object' && 'text' in c) return String((c as { text: unknown }).text);
        return '';
      })
      .filter(Boolean);
    return parts.join(' ');
  }
  return undefined;
}

function collectAuditSummary(cutoff: Date): ToolCount[] {
  const auditPath = path.join(CLAUDE_DIR, 'audit.jsonl');
  if (!fs.existsSync(auditPath)) return [];
  const counts = new Map<string, number>();
  let content: string;
  try {
    content = fs.readFileSync(auditPath, 'utf8');
  } catch {
    return [];
  }

  for (const line of content.split('\n')) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line) as Record<string, unknown>;
      const ts = (parsed.timestamp ?? parsed.time ?? parsed.ts) as string | undefined;
      if (!ts) continue;
      const d = new Date(ts);
      if (Number.isNaN(d.getTime()) || d < cutoff) continue;
      const tool = String(parsed.tool ?? parsed.toolName ?? 'unknown');
      counts.set(tool, (counts.get(tool) ?? 0) + 1);
    } catch {
      // skip
    }
  }

  return Array.from(counts, ([tool, count]) => ({ tool, count })).sort(
    (a, b) => b.count - a.count,
  );
}

function collectGitActivity(repos: string[], cutoff: Date): GitActivity[] {
  const since = cutoff.toISOString().slice(0, 10);
  const results: GitActivity[] = [];
  for (const repo of repos) {
    if (!fs.existsSync(path.join(repo, '.git'))) continue;
    const log = tryExec(
      `git -C "${repo}" log --since="${since}" --pretty=format:%H%x1f%ad%x1f%s --date=short`,
    );
    if (!log) {
      results.push({ repo, commits: [] });
      continue;
    }
    const commits = log
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const [sha, date, ...msg] = line.split('\x1f');
        return { sha: sha ?? '', date: date ?? '', message: msg.join(' ') };
      });
    results.push({ repo, commits });
  }
  return results;
}

function tryExec(cmd: string): string | undefined {
  try {
    return execSync(cmd, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return undefined;
  }
}

function readIfExists(p: string): string | undefined {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return undefined;
  }
}

function safeReaddir(dir: string): string[] {
  try {
    return fs.readdirSync(dir);
  } catch {
    return [];
  }
}

function listFiles(dir: string, ext: string): string[] {
  return safeReaddir(dir).filter((f) => f.endsWith(ext));
}

function listDirs(dir: string): string[] {
  try {
    return fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch {
    return [];
  }
}
