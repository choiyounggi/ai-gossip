#!/usr/bin/env node
import { Command } from 'commander';
import { loadPublicProfile } from './profile.ts';
import { createClaudeRunner } from './claude.ts';
import { buildTurnPrompt } from './prompt.ts';
import { connect } from './ws.ts';
import type { ServerToClient } from './protocol.ts';

interface CliOptions {
  server: string;
  room: string;
  user: string;
  name?: string;
  claudeBin?: string;
  echo?: boolean;
}

const program = new Command();
program
  .name('ai-gossip-runner')
  .description('Local Runner — bridges claude -p with the battle server')
  .requiredOption('--server <url>', 'WebSocket server URL (e.g. ws://localhost:8787)')
  .requiredOption('--room <id>', 'Room id to join')
  .requiredOption('--user <id>', 'Your userId in the room')
  .option('--name <display>', 'Display name (defaults to userId)')
  .option('--claude-bin <path>', 'Override path to claude binary')
  .option('--echo', 'Do not call claude; just echo a canned string (debug mode)')
  .parse(process.argv);

const opts = program.opts<CliOptions>();
const userName = opts.name ?? opts.user;

const profile = loadPublicProfile();
console.log(`[runner] loaded profile (created ${profile.createdAt})`);

const claude = opts.echo
  ? { run: async (_: string): Promise<string> => `(echo from ${userName})` }
  : createClaudeRunner({ claudeBin: opts.claudeBin });

/** Highest seq we've observed; sent back on reconnect as `sinceSeq` so the
 *  server can replay messages that landed while we were disconnected. */
let lastSeq = 0;

const client = connect(opts.server, {
  onOpen: () => {
    console.log(`[runner] connected; joining room "${opts.room}" as ${userName}`);
    client.send({
      type: 'JOIN_ROOM',
      roomId: opts.room,
      userId: opts.user,
      userName,
      publicProfile: profile.publicYaml,
    });
  },
  onReconnect: () => {
    console.log(
      `[runner] reconnected; resuming room "${opts.room}" (sinceSeq=${lastSeq})`,
    );
    client.send({
      type: 'JOIN_ROOM',
      roomId: opts.room,
      userId: opts.user,
      userName,
      publicProfile: profile.publicYaml,
      sinceSeq: lastSeq,
    });
  },
  onMessage: (msg: ServerToClient) => void handleServerMessage(msg),
  onClose: (code, reason) => {
    console.log(`[runner] socket closed (${code}) ${reason}`);
    process.exit(0);
  },
  onError: (err) => {
    console.error('[runner] ws error:', err.message);
  },
});

process.on('SIGINT', () => {
  console.log('\n[runner] SIGINT, leaving room');
  client.send({ type: 'LEAVE', roomId: opts.room, userId: opts.user });
  setTimeout(() => process.exit(0), 300);
});

async function handleServerMessage(msg: ServerToClient): Promise<void> {
  switch (msg.type) {
    case 'JOINED':
      console.log(
        `[runner] participants: ${msg.participants.map((p) => p.userName).join(', ')}`,
      );
      break;
    case 'ROOM_SNAPSHOT':
      // Either late-joiner snapshot (last HISTORY_WINDOW) or reconnect replay
      // (messages with seq > sinceSeq). Either way, advance lastSeq so the
      // next disconnect asks for the right window.
      for (const m of msg.history) {
        if (m.seq > lastSeq) lastSeq = m.seq;
        console.log(`[chat] ${m.userName}: ${m.content}`);
      }
      break;
    case 'ROOM_UPDATE':
      if (msg.message.seq > lastSeq) lastSeq = msg.message.seq;
      console.log(`[chat] ${msg.message.userName}: ${msg.message.content}`);
      break;
    case 'YOUR_TURN': {
      for (const m of msg.history) {
        if (m.seq > lastSeq) lastSeq = m.seq;
      }
      const prompt = buildTurnPrompt({
        selfUserId: opts.user,
        selfName: userName,
        selfPublicProfile: profile.publicYaml,
        participants: msg.participants,
        history: msg.history,
      });
      console.log(`[runner] turn ${msg.turn}: generating...`);
      try {
        const reply = await claude.run(prompt);
        client.send({
          type: 'MESSAGE',
          roomId: opts.room,
          userId: opts.user,
          content: reply,
        });
      } catch (err) {
        console.error(
          '[runner] claude failed:',
          err instanceof Error ? err.message : String(err),
        );
        client.send({
          type: 'MESSAGE',
          roomId: opts.room,
          userId: opts.user,
          content: '(응답 생성 실패, 다음 턴으로 넘깁니다)',
        });
      }
      break;
    }
    case 'ROOM_CLOSED':
      console.log(`[runner] room closed: ${msg.reason}`);
      client.close();
      break;
    case 'ERROR':
      console.error('[runner] server error:', msg.reason);
      break;
  }
}
