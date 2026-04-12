# GearSnitch Conductor Workspace

This directory is the repo-local state surface for the GearSnitch `/loop` workflow.

## Core Files

- `conductor/workflow.md` — loop contract and operator instructions
- `conductor/tracks.md` — active track registry and sequencing
- `conductor/product.md` — product scope and current user-facing goals
- `conductor/tech-stack.md` — architecture, commands, and delivery constraints
- `conductor/product-roadmap.md` — staged delivery order for the unfinished backlog
- `conductor/screen-map.md` — current surface inventory by platform
- `conductor/decision-log.md` — high-impact architectural or product decisions
- `conductor/knowledge/` — durable patterns and recurring failure modes

## Track Structure

Each track lives in `conductor/tracks/<track_id>/` with:

- `spec.md` — requirements and acceptance criteria
- `plan.md` — phased execution plan generated during Step 1
- `metadata.json` — persistent loop state and dependency metadata

## Practical Usage

This repo cannot install a native global slash command by itself. The contract here is:

- In chat, use prompts like `/loop status`, `/loop next`, `/loop start <track-id>`, or `/loop resume <track-id>`
- In the terminal, use `node scripts/loop.mjs status|next|show <track-id>` for deterministic state inspection

The workflow is intentionally repo-local so the next session can resume from files instead of chat memory.
