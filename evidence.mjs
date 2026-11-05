// Trims a `claude -p --output-format stream-json` log to the facts the README relies on,
// without any prompt or answer text: Claude Code version, model and plugin list from the
// start-up event, every tool call (with the skill name for Skill calls), and the result's
// time, turns, output tokens and cost.
// Usage: node evidence.mjs out/plugins-on.jsonl > out/plugins-on.evidence.json
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) { console.error('usage: node evidence.mjs <run.jsonl>'); process.exit(2); }

const evidence = { log: file, start: null, toolCalls: [], result: null };
for (const line of readFileSync(file, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  let ev;
  try { ev = JSON.parse(line); } catch { continue; }
  if (ev.type === 'system' && ev.subtype === 'init') {
    evidence.start = {
      claudeCodeVersion: ev.claude_code_version ?? null,
      model: ev.model ?? null,
      plugins: (ev.plugins ?? []).map(p => (typeof p === 'string' ? p : p.name)),
      skills: ev.skills ?? [],
    };
  } else if (ev.type === 'assistant') {
    for (const block of ev.message?.content ?? []) {
      if (block.type !== 'tool_use') continue;
      evidence.toolCalls.push(block.name === 'Skill' ? `Skill:${block.input?.skill ?? '?'}` : block.name);
    }
  } else if (ev.type === 'result') {
    const outputTokens = ev.usage?.output_tokens ?? null;
    evidence.result = {
      subtype: ev.subtype ?? null,
      isError: ev.is_error ?? null,
      turns: ev.num_turns ?? null,
      durationMs: ev.duration_ms ?? null,
      outputTokens,
      msPer1000OutputTokens: outputTokens && ev.duration_ms ? Math.round(ev.duration_ms / outputTokens * 1000) : null,
      // API-equivalent figure: on a subscription plan the run uses plan usage, not money.
      costUsd: ev.total_cost_usd ?? null,
    };
  }
}
if (!evidence.start) console.error(`${file}: no start-up (init) event found`);
console.log(JSON.stringify(evidence, null, 2));
