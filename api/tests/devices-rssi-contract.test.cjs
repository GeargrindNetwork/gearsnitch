const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

/**
 * Contract test for the RSSI signal-history feature (backlog item #19).
 *
 * Verifies:
 *   - `RssiSample` model exports + indexes exist (TTL + compound).
 *   - `POST /devices/:id/rssi` is mounted, authenticated, validated,
 *     and wired to `RssiSample.insertMany`.
 *   - `GET /devices/:id/rssi/history` is mounted, authenticated, and
 *     exposes the documented response shape.
 *   - `bucketRssiSamples` + `computeWeekOverWeekDelta` are exported
 *     for the runtime test to import.
 *   - iOS side exposes `RssiSampleBuffer`, `SignalHistoryService`, and
 *     the chart section on `DeviceDetailView`.
 */
describe('RSSI signal history (item #19) contract', () => {
  const rssiModel = read('api/src/models/RssiSample.ts');
  const modelsIndex = read('api/src/models/index.ts');
  const deviceRoutes = read('api/src/modules/devices/routes.ts');
  const rssiBuffer = read('client-ios/GearSnitch/Core/BLE/RssiSampleBuffer.swift');
  const signalService = read(
    'client-ios/GearSnitch/Features/Devices/SignalHistoryService.swift'
  );
  const signalVM = read(
    'client-ios/GearSnitch/Features/Devices/SignalHistoryViewModel.swift'
  );
  const deviceDetailView = read(
    'client-ios/GearSnitch/Features/Devices/DeviceDetailView.swift'
  );
  const bleManager = read('client-ios/GearSnitch/Core/BLE/BLEManager.swift');

  test('RssiSample model exposes the expected fields', () => {
    expect(rssiModel).toContain('userId: Types.ObjectId');
    expect(rssiModel).toContain('deviceId: Types.ObjectId');
    expect(rssiModel).toContain('rssi: number');
    expect(rssiModel).toContain('sampledAt: Date');
    expect(rssiModel).toContain('min: -120,');
    expect(rssiModel).toContain('max: 0,');
  });

  test('RssiSample has a TTL index and a compound deviceId+sampledAt index', () => {
    expect(rssiModel).toContain('expireAfterSeconds: 60 * 60 * 24 * 7');
    expect(rssiModel).toMatch(/index\(\s*\{\s*deviceId:\s*1,\s*sampledAt:\s*-1\s*\}/);
  });

  test('RssiSample model is exported from the models barrel', () => {
    expect(modelsIndex).toContain("export { RssiSample } from './RssiSample'");
    expect(modelsIndex).toContain("export type { IRssiSample } from './RssiSample'");
  });

  test('POST /devices/:id/rssi is mounted + authenticated + validated', () => {
    expect(deviceRoutes).toContain("router.post(\n  '/:id/rssi',");
    expect(deviceRoutes).toContain('validateBody(ingestRssiSchema)');
    expect(deviceRoutes).toMatch(/router\.post\(\s*'\/\:id\/rssi',\s*isAuthenticated/);
    expect(deviceRoutes).toContain('RssiSample.insertMany');
    expect(deviceRoutes).toContain('RSSI_BATCH_LIMIT');
  });

  test('RSSI batch caps at 100 samples', () => {
    expect(deviceRoutes).toContain('export const RSSI_BATCH_LIMIT = 100');
    expect(deviceRoutes).toMatch(/\.max\(RSSI_BATCH_LIMIT/);
  });

  test('RSSI schema validates rssi is in [-120, 0]', () => {
    expect(deviceRoutes).toContain('z.number().finite().min(-120).max(0)');
  });

  test('GET /devices/:id/rssi/history is mounted + authenticated', () => {
    expect(deviceRoutes).toContain("router.get('/:id/rssi/history', isAuthenticated");
    expect(deviceRoutes).toContain('windowHours');
    expect(deviceRoutes).toContain('weekOverWeekDelta');
    expect(deviceRoutes).toContain('lifetimeAvg');
  });

  test('Bucketing + WoW helpers are exported for runtime tests', () => {
    expect(deviceRoutes).toContain('export function bucketRssiSamples');
    expect(deviceRoutes).toContain('export function computeWeekOverWeekDelta');
  });

  test('iOS RssiSampleBuffer has 5-min / 20-sample flush triggers', () => {
    expect(rssiBuffer).toContain('defaultMaxBatchSize = 20');
    expect(rssiBuffer).toContain('defaultFlushInterval: TimeInterval = 5 * 60');
    expect(rssiBuffer).toContain('func record(');
    expect(rssiBuffer).toContain('func flushAll()');
    expect(rssiBuffer).toContain('func shouldFlush(buffer:');
  });

  test('iOS SignalHistoryService hits the 24h history endpoint', () => {
    expect(signalService).toContain('/api/v1/devices/');
    expect(signalService).toContain('/rssi/history');
    expect(signalService).toContain('windowHours');
    expect(signalService).toContain('buckets');
    expect(signalService).toContain('weekOverWeekDelta');
  });

  test('iOS SignalHistoryViewModel exposes warning threshold at -15 dBm', () => {
    expect(signalVM).toContain('weekOverWeekWarningThreshold: Double = -15');
    expect(signalVM).toContain('shouldShowWeeklyDropWarning');
  });

  test('DeviceDetailView renders Signal History section + chart', () => {
    expect(deviceDetailView).toContain('import Charts');
    expect(deviceDetailView).toContain('signalHistoryViewModel');
    expect(deviceDetailView).toContain('Signal History');
    expect(deviceDetailView).toContain('LineMark(');
    expect(deviceDetailView).toContain('Signal dropped');
    expect(deviceDetailView).toContain('Check device placement or battery');
  });

  test('BLEManager wires RssiSampleBuffer into discovery + readRSSI', () => {
    expect(bleManager).toContain('let rssiSampleBuffer = RssiSampleBuffer()');
    expect(bleManager).toMatch(
      /self\.rssiSampleBuffer\.record\(\s*rssi:\s*RSSI\.intValue/
    );
    expect(bleManager).toMatch(
      /self\.rssiSampleBuffer\.record\(\s*rssi:\s*rssiValue/
    );
  });
});
