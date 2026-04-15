const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('heart rate integration contract', () => {
  const healthRoutes = read('src/modules/health/routes.ts');
  const healthMetricModel = read('src/models/HealthMetric.ts');
  const sharedSchemas = readRepo('shared/src/schemas/index.ts');

  // ── Model ──

  test('HealthMetric model supports heart_rate metricType', () => {
    expect(healthMetricModel).toContain("'heart_rate'");
  });

  test('HealthMetric model supports airpods_pro source', () => {
    expect(healthMetricModel).toContain("'airpods_pro'");
  });

  test('HealthMetric model has ascending index for time-window queries', () => {
    expect(healthMetricModel).toContain('{ userId: 1, metricType: 1, recordedAt: 1 }');
  });

  // ── Routes ──

  test('health routes expose heart rate batch endpoint', () => {
    expect(healthRoutes).toContain("router.post('/heart-rate/batch', isAuthenticated");
  });

  test('health routes expose heart rate session summary endpoint', () => {
    expect(healthRoutes).toContain("router.get('/heart-rate/session-summary', isAuthenticated");
  });

  test('health routes expose unified dashboard endpoint', () => {
    expect(healthRoutes).toContain("router.get('/dashboard', isAuthenticated");
  });

  test('health routes expose trends endpoint', () => {
    expect(healthRoutes).toContain("router.get('/trends', isAuthenticated");
  });

  test('heart rate batch handler performs bulkWrite with deduplication', () => {
    expect(healthRoutes).toContain('handleHeartRateBatch');
    expect(healthRoutes).toContain('$setOnInsert');
  });

  test('session summary handler computes zone distribution', () => {
    expect(healthRoutes).toContain('classifyHeartRateZone');
    expect(healthRoutes).toContain('zoneDistribution');
  });

  test('normalizeMetricType maps heart_rate and instantaneous_heart_rate', () => {
    expect(healthRoutes).toContain("case 'heart_rate':");
    expect(healthRoutes).toContain("case 'instantaneous_heart_rate':");
  });

  test('normalizeMetricSource maps airpods_pro', () => {
    expect(healthRoutes).toContain("'airpods_pro'");
    expect(healthRoutes).toMatch(/airpods/);
  });

  // ── Zone classification ──

  test('classifyHeartRateZone returns correct zone boundaries', () => {
    expect(healthRoutes).toContain("if (bpm < 100) return 'rest'");
    expect(healthRoutes).toContain("if (bpm < 120) return 'light'");
    expect(healthRoutes).toContain("if (bpm < 140) return 'fatBurn'");
    expect(healthRoutes).toContain("if (bpm < 160) return 'cardio'");
    expect(healthRoutes).toContain("return 'peak'");
  });

  // ── Dashboard ──

  test('dashboard handler aggregates HR, sessions, devices, and sources', () => {
    expect(healthRoutes).toContain('handleHealthDashboard');
    expect(healthRoutes).toContain('latestHR');
    expect(healthRoutes).toContain('todayHRSamples');
    expect(healthRoutes).toContain('todaySessions');
    expect(healthRoutes).toContain('devices');
    expect(healthRoutes).toContain('sourceCounts');
  });

  test('dashboard imports Device and GymSession models', () => {
    expect(healthRoutes).toContain("import { Device } from '../../models/Device.js'");
    expect(healthRoutes).toContain("import { GymSession } from '../../models/GymSession.js'");
  });

  // ── Trends ──

  test('trends handler returns all six data series', () => {
    expect(healthRoutes).toContain('handleHealthTrends');
    expect(healthRoutes).toContain('heartRateScatter');
    expect(healthRoutes).toContain('restingHeartRate');
    expect(healthRoutes).toContain('weightTrend');
    expect(healthRoutes).toContain('caloriesTrend');
    expect(healthRoutes).toContain('workoutTrend');
  });

  // ── Shared schemas ──

  test('shared schemas export heart rate batch and session summary types', () => {
    expect(sharedSchemas).toContain('heartRateSampleSchema');
    expect(sharedSchemas).toContain('heartRateBatchSchema');
    expect(sharedSchemas).toContain('heartRateZoneDistributionSchema');
    expect(sharedSchemas).toContain('heartRateSessionSummarySchema');
  });

  test('shared schemas export health dashboard types', () => {
    expect(sharedSchemas).toContain('healthDashboardResponseSchema');
    expect(sharedSchemas).toContain('healthDashboardLatestHRSchema');
    expect(sharedSchemas).toContain('healthDashboardDeviceSchema');
    expect(sharedSchemas).toContain('healthDashboardSourceSchema');
  });

  test('shared schemas export health trends types', () => {
    expect(sharedSchemas).toContain('healthTrendsResponseSchema');
    expect(sharedSchemas).toContain('healthTrendsHRPointSchema');
    expect(sharedSchemas).toContain('healthTrendsWorkoutPointSchema');
  });

  test('shared schemas include bpm validation range 30-250', () => {
    expect(sharedSchemas).toMatch(/bpm.*min\(30\).*max\(250\)/s);
  });
});
