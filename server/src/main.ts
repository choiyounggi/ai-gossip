#!/usr/bin/env node
import { Command } from 'commander';
import { startServer } from './ws.ts';

const program = new Command();
program
  .name('ai-gossip-server')
  .description('AI Gossip battle server (Phase 2)')
  .option('-p, --port <number>', 'WebSocket port', '8787')
  .parse(process.argv);

const opts = program.opts<{ port: string }>();
const port = Number.parseInt(opts.port, 10);
if (!Number.isFinite(port) || port <= 0 || port > 65535) {
  console.error(`invalid port: ${opts.port}`);
  process.exit(1);
}

startServer({ port });

process.on('SIGINT', () => {
  console.log('\n[server] SIGINT received, shutting down');
  process.exit(0);
});
