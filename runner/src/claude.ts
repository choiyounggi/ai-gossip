import { spawn } from 'node:child_process';

export interface RunClaudeOptions {
  claudeBin?: string;
  timeoutMs?: number;
  maxRetries?: number;
}

export interface ClaudeRunner {
  run(prompt: string): Promise<string>;
}

/**
 * Real implementation: shells out to `claude -p` and returns trimmed stdout.
 * Retries on non-zero exit or timeout up to `maxRetries` times.
 */
export function createClaudeRunner(opts: RunClaudeOptions = {}): ClaudeRunner {
  const bin = opts.claudeBin ?? 'claude';
  const timeoutMs = opts.timeoutMs ?? 120_000;
  const maxRetries = opts.maxRetries ?? 2;

  return {
    async run(prompt: string): Promise<string> {
      let lastErr: unknown;
      for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
        try {
          return await runOnce(bin, prompt, timeoutMs);
        } catch (err) {
          lastErr = err;
          const delay = 500 * 2 ** attempt;
          await sleep(delay);
        }
      }
      throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
    },
  };
}

// gossip은 순수 텍스트 생성만 필요 → 모든 도구/사용자 MCP를 차단해 TCC 프롬프트(파일·음악 등) 억제.
const GOSSIP_FLAGS = [
  '--tools', '',
  '--strict-mcp-config',
  '--mcp-config', '{"mcpServers":{}}',
  '--permission-mode', 'bypassPermissions',
];

function runOnce(bin: string, prompt: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, ['-p', ...GOSSIP_FLAGS], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      reject(new Error(`claude -p timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on('data', (d: Buffer) => {
      stdout += d.toString();
    });
    child.stderr.on('data', (d: Buffer) => {
      stderr += d.toString();
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve(stdout.trim());
      } else {
        reject(new Error(`claude -p exited with code ${code}: ${stderr.trim()}`));
      }
    });

    child.stdin.write(prompt);
    child.stdin.end();
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
