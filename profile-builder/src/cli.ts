#!/usr/bin/env node
import { Command } from 'commander';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { fileURLToPath } from 'node:url';
import { collect } from './collect.ts';
import { generateDraftProfile } from './abstract.ts';
import { loadDenylist, regexRedact, llmReview } from './guard.ts';
import { saveCache, loadCache, isExpired } from './cache.ts';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');
const CONFIG_DIR = path.join(PROJECT_ROOT, 'config');
const DEFAULT_CACHE_DIR = path.join(os.homedir(), '.ai-gossip', 'cache');

interface BuildOptions {
  skipLlm?: boolean;
  claudeBin?: string;
}

async function buildProfile(repos: string[], opts: BuildOptions): Promise<void> {
  console.log('[1/4] Collecting...');
  const raw = collect({ whitelistedRepos: repos });
  console.log(`  sessions=${raw.sessionSamples.length}`);
  console.log(`  skills=${raw.tools.skillNames.length}`);
  console.log(`  plugins=${raw.tools.pluginNames.length}`);
  console.log(`  hooks=${raw.settings.hookKeys.length}`);
  console.log(`  audit_tools=${raw.auditSummary.length}`);
  console.log(`  git_repos=${raw.gitActivity.length}`);

  if (opts.skipLlm) {
    fs.mkdirSync(DEFAULT_CACHE_DIR, { recursive: true });
    const rawOutPath = path.join(DEFAULT_CACHE_DIR, 'raw-debug.json');
    fs.writeFileSync(rawOutPath, JSON.stringify(raw, null, 2));
    console.log(`[2/4] Skipped (--skip-llm). raw-debug.json: ${rawOutPath}`);
    return;
  }

  console.log('[2/4] Abstracting via claude -p ...');
  const abstractPromptPath = path.join(CONFIG_DIR, 'prompts', 'abstract.md');
  const draft = generateDraftProfile(raw, abstractPromptPath, {
    claudeBin: opts.claudeBin,
  });

  console.log('[3/4] Guard pass 1: regex redact...');
  const denylist = loadDenylist(path.join(CONFIG_DIR, 'denylist.json'));
  const { filtered: redacted, redactions } = regexRedact(draft, denylist);
  if (redactions.length === 0) {
    console.log('  (no matches)');
  } else {
    for (const r of redactions) {
      console.log(`  redacted ${r.name}: ${r.count}`);
    }
  }

  console.log('[4/4] Guard pass 2: LLM filter...');
  const filterPromptPath = path.join(CONFIG_DIR, 'prompts', 'filter.md');
  const finalYaml = llmReview(redacted, filterPromptPath, {
    claudeBin: opts.claudeBin,
  });

  saveCache({
    cacheDir: DEFAULT_CACHE_DIR,
    internal: raw,
    draftYaml: draft,
    publicYaml: finalYaml,
  });
  console.log(`\nSaved: ${DEFAULT_CACHE_DIR}`);
  console.log('Run: ai-gossip profile show');
}

function showAction(options: { internal?: boolean }): void {
  const cached = loadCache(DEFAULT_CACHE_DIR);
  if (cached === null) {
    console.error('No profile yet. Run: ai-gossip profile init --repo <path>');
    process.exit(1);
  }
  console.log('--- PUBLIC PROFILE ---');
  console.log(cached.publicYaml);
  if (options.internal) {
    console.log('\n--- INTERNAL (raw, local-only) ---');
    console.log(JSON.stringify(cached.internal, null, 2));
    if (cached.draftYaml) {
      console.log('\n--- DRAFT (pre-guard) ---');
      console.log(cached.draftYaml);
    }
  }
  const expired = isExpired(cached);
  console.log(`\nCreated: ${cached.createdAt}`);
  console.log(`TTL: ${cached.ttlDays}d — ${expired ? 'EXPIRED (rebuild recommended)' : 'fresh'}`);
}

function buildProgram(): Command {
  const program = new Command();
  program
    .name('ai-gossip')
    .description('AI Gossip — profile builder POC')
    .version('0.1.0');

  const profile = program
    .command('profile')
    .description('Profile commands');

  profile
    .command('init')
    .description('Build profile for the first time')
    .option('-r, --repo <paths...>', 'Whitelisted repo paths', [])
    .option('--skip-llm', 'Skip LLM steps (collect only)')
    .option('--claude-bin <path>', 'Override claude binary path')
    .action(async (opts: { repo: string[]; skipLlm?: boolean; claudeBin?: string }) => {
      await buildProfile(opts.repo, { skipLlm: opts.skipLlm, claudeBin: opts.claudeBin });
    });

  profile
    .command('rebuild')
    .description('Force rebuild profile')
    .option('-r, --repo <paths...>', 'Whitelisted repo paths', [])
    .option('--skip-llm', 'Skip LLM steps')
    .option('--claude-bin <path>', 'Override claude binary path')
    .action(async (opts: { repo: string[]; skipLlm?: boolean; claudeBin?: string }) => {
      await buildProfile(opts.repo, { skipLlm: opts.skipLlm, claudeBin: opts.claudeBin });
    });

  profile
    .command('show')
    .description('Show current public profile')
    .option('--internal', 'Also show internal raw data')
    .action(showAction);

  return program;
}

buildProgram().parseAsync(process.argv).catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
