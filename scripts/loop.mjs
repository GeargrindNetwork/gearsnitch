#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const conductorDir = path.join(root, 'conductor');
const tracksDir = path.join(conductorDir, 'tracks');

const priorityOrder = new Map([
  ['P0', 0],
  ['P1', 1],
  ['P2', 2],
  ['P3', 3],
]);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function loadTrack(trackId) {
  const trackRoot = path.join(tracksDir, trackId);
  const metadataPath = path.join(trackRoot, 'metadata.json');
  const specPath = path.join(trackRoot, 'spec.md');
  const planPath = path.join(trackRoot, 'plan.md');

  if (!fs.existsSync(metadataPath)) {
    return null;
  }

  const metadata = loadJson(metadataPath);
  return {
    id: trackId,
    root: trackRoot,
    metadataPath,
    specPath,
    planPath,
    metadata,
  };
}

function loadTracks() {
  if (!fs.existsSync(tracksDir)) {
    fail('No conductor workspace found. Expected conductor/tracks/.');
  }

  return fs.readdirSync(tracksDir)
    .filter((entry) => fs.statSync(path.join(tracksDir, entry)).isDirectory())
    .map(loadTrack)
    .filter(Boolean);
}

function isComplete(track) {
  const { metadata } = track;
  return metadata.status === 'complete'
    || metadata.loop_state?.current_step === 'COMPLETE'
    || metadata.loop_state?.step_status === 'PASSED' && metadata.loop_state?.checkpoints?.ENRICH?.status === 'PASSED';
}

function depsSatisfied(track, byId) {
  const deps = track.metadata.dependencies || [];
  return deps.every((dep) => {
    const depTrack = byId.get(dep);
    return depTrack && isComplete(depTrack);
  });
}

function nextAction(track) {
  const state = track.metadata.loop_state || {};
  const step = state.current_step || 'NOT_STARTED';
  const status = state.step_status || 'NOT_STARTED';

  if (step === 'NOT_STARTED') {
    return `/loop start ${track.id}`;
  }

  if (status === 'FAILED') {
    return `/loop fix ${track.id}`;
  }

  return `/loop resume ${track.id}`;
}

function printTrack(track) {
  const { metadata } = track;
  const state = metadata.loop_state || {};
  console.log(`${track.id}`);
  console.log(`  name: ${metadata.name}`);
  console.log(`  priority: ${metadata.priority}`);
  console.log(`  status: ${state.current_step || 'NOT_STARTED'} / ${state.step_status || 'NOT_STARTED'}`);
  console.log(`  depends_on: ${(metadata.dependencies || []).join(', ') || '—'}`);
  console.log(`  next: ${nextAction(track)}`);
}

function showStatus() {
  const tracks = loadTracks();
  const byId = new Map(tracks.map((track) => [track.id, track]));

  console.log(`GearSnitch loop status`);
  console.log(`repo: ${root}`);
  console.log('');

  for (const track of tracks) {
    printTrack(track);
    console.log(`  ready: ${depsSatisfied(track, byId) ? 'yes' : 'no'}`);
    console.log('');
  }
}

function pickNext() {
  const tracks = loadTracks();
  const byId = new Map(tracks.map((track) => [track.id, track]));

  const candidates = tracks
    .filter((track) => !isComplete(track))
    .filter((track) => depsSatisfied(track, byId))
    .sort((left, right) => {
      const leftPriority = priorityOrder.get(left.metadata.priority) ?? 99;
      const rightPriority = priorityOrder.get(right.metadata.priority) ?? 99;
      if (leftPriority !== rightPriority) {
        return leftPriority - rightPriority;
      }
      return left.id.localeCompare(right.id);
    });

  if (candidates.length === 0) {
    console.log('No unblocked tracks found.');
    return;
  }

  const track = candidates[0];
  console.log(`Next track: ${track.id}`);
  console.log(`Name: ${track.metadata.name}`);
  console.log(`Summary: ${track.metadata.summary}`);
  console.log(`Suggested prompt: ${nextAction(track)}`);
  console.log(`Spec: ${path.relative(root, track.specPath)}`);
  console.log(`Plan: ${path.relative(root, track.planPath)}`);
  console.log(`Metadata: ${path.relative(root, track.metadataPath)}`);
}

function showTrack(trackId) {
  const track = loadTrack(trackId);
  if (!track) {
    fail(`Unknown track: ${trackId}`);
  }

  printTrack(track);
  console.log(`  spec: ${path.relative(root, track.specPath)}`);
  console.log(`  plan: ${path.relative(root, track.planPath)}`);
  console.log(`  metadata: ${path.relative(root, track.metadataPath)}`);
}

const [command = 'status', arg] = process.argv.slice(2);

if (!fs.existsSync(conductorDir)) {
  fail('No conductor workspace found. Expected conductor/.');
}

switch (command) {
  case 'status':
    showStatus();
    break;
  case 'next':
    pickNext();
    break;
  case 'show':
    if (!arg) {
      fail('Usage: node scripts/loop.mjs show <track-id>');
    }
    showTrack(arg);
    break;
  default:
    fail('Usage: node scripts/loop.mjs [status|next|show <track-id>]');
}
