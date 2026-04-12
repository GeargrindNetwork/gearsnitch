const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('realtime and worker hardening regression sweep', () => {
  const notificationRoutes = read('api/src/modules/notifications/routes.ts');
  const workerRuntime = read('worker/src/utils/jobRuntime.ts');
  const pushNotificationJob = read('worker/src/jobs/pushNotification.ts');
  const alertFanoutJob = read('worker/src/jobs/alertFanout.ts');
  const referralQualificationJob = read('worker/src/jobs/referralQualification.ts');
  const referralRewardJob = read('worker/src/jobs/referralReward.ts');
  const subscriptionValidationJob = read('worker/src/jobs/subscriptionValidation.ts');
  const storeOrderJob = read('worker/src/jobs/storeOrder.ts');
  const dataExportJob = read('worker/src/jobs/dataExport.ts');
  const socketAuth = read('realtime/src/utils/socketAuth.ts');
  const runtimeEvents = read('realtime/src/utils/runtimeEvents.ts');
  const realtimeServer = read('realtime/src/index.ts');

  test('notification routes are live and no longer ship placeholder handlers', () => {
    expect(notificationRoutes).toContain("router.get('/', isAuthenticated");
    expect(notificationRoutes).toContain("router.patch('/:id/read', isAuthenticated");
    expect(notificationRoutes).toContain("router.post('/read-all', isAuthenticated");
    expect(notificationRoutes).toContain("router.get('/preferences', isAuthenticated");
    expect(notificationRoutes).toContain("router.patch('/preferences', isAuthenticated");
    expect(notificationRoutes).toContain("router.post('/register', isAuthenticated");
    expect(notificationRoutes).not.toContain('not yet implemented');
    expect(notificationRoutes).toContain('NotificationLog.find(filter)');
    expect(notificationRoutes).toContain('NotificationToken.findOneAndUpdate(');
  });

  test('worker runtime exposes idempotency and realtime event helpers', () => {
    expect(workerRuntime).toContain('export async function withIdempotency(');
    expect(workerRuntime).toContain('export async function publishRuntimeEvent(');
    expect(workerRuntime).toContain('export function recordFromUnknown(');
  });

  test('worker jobs are implemented without TODO placeholders', () => {
    const jobSources = [
      pushNotificationJob,
      alertFanoutJob,
      referralQualificationJob,
      referralRewardJob,
      subscriptionValidationJob,
      storeOrderJob,
      dataExportJob,
    ];

    for (const source of jobSources) {
      expect(source).not.toContain('TODO:');
      expect(source).not.toContain('console.log(');
      expect(source).toContain('recordFromUnknown(job.data)');
    }
  });

  test('realtime auth validates API-compatible redis sessions', () => {
    expect(socketAuth).toContain("const algorithm = isProduction ? 'RS256' : 'HS256'");
    expect(socketAuth).toContain('`session:${decoded.sub}:${decoded.jti}`');
    expect(socketAuth).not.toContain('whitelist:auth:');
  });

  test('realtime service uses normalized event channels and iOS-facing event names', () => {
    expect(runtimeEvents).toContain('runtimeEventEnvelopeSchema');
    expect(runtimeEvents).toContain('parseRuntimeEvent');
    expect(runtimeEvents).toContain('roomForEvent');
    expect(alertFanoutJob).toContain("eventName: 'alert:new'");
    expect(subscriptionValidationJob).toContain("eventName: 'subscription:update'");
    expect(referralQualificationJob).toContain("eventName: 'referral:update'");
    expect(referralRewardJob).toContain("eventName: 'referral:update'");
    expect(storeOrderJob).toContain("eventName: 'store:order:update'");
    expect(realtimeServer).toContain("const stateRedis = new IORedis(REDIS_URL, {");
    expect(realtimeServer).toContain("keyPrefix: 'gs:'");
    expect(realtimeServer).toContain("eventName: 'device:status'");
    expect(realtimeServer).toContain("case 'events:alert':");
    expect(realtimeServer).toContain("case 'events:subscription':");
    expect(realtimeServer).toContain("case 'events:referral':");
    expect(realtimeServer).toContain("case 'events:store-order':");
    expect(realtimeServer).toContain("deviceNs.to(room).emit(event.eventName, event.payload)");
  });
});
