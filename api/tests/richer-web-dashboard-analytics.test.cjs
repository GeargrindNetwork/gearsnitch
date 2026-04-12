const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('richer web dashboard analytics regression sweep', () => {
  const workoutRoutes = read('api/src/modules/workouts/routes.ts');
  const metricsPage = read('web/src/pages/MetricsPage.tsx');

  test('metrics overview route now aggregates run and device analytics', () => {
    expect(workoutRoutes).toContain("import { Run } from '../../models/Run.js';");
    expect(workoutRoutes).toContain("import { Device } from '../../models/Device.js';");
    expect(workoutRoutes).toContain('function serializeRunMetricsCard(run: Record<string, any>)');
    expect(workoutRoutes).toContain('function serializeDeviceMetricsCard(device: Record<string, any>)');
    expect(workoutRoutes).toContain('function buildDistanceTrend(thisWeekDistanceMeters: number, lastWeekDistanceMeters: number)');
    expect(workoutRoutes).toContain('runSummary: {');
    expect(workoutRoutes).toContain('runTrend: buildDistanceTrend(thisWeekDistanceMeters, lastWeekDistanceMeters),');
    expect(workoutRoutes).toContain('deviceSummary: {');
    expect(workoutRoutes).toContain('devices: deviceCards,');
    expect(workoutRoutes).toContain('recentRuns: recentRuns.map(serializeRunMetricsCard),');
  });

  test('metrics page renders the richer run and device dashboard surfaces', () => {
    expect(metricsPage).toContain('Workouts, runs, and device state in one browser dashboard.');
    expect(metricsPage).toContain('Run Distance Trend');
    expect(metricsPage).toContain('Device Fleet');
    expect(metricsPage).toContain('Device Status');
    expect(metricsPage).toContain('Recent Runs');
    expect(metricsPage).toContain('Open /runs');
    expect(metricsPage).toContain('data.runSummary.totalDistanceMeters');
    expect(metricsPage).toContain('data.devices.length > 0');
    expect(metricsPage).toContain('Link to="/runs"');
  });
});
