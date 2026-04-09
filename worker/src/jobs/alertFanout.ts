export async function processAlertFanout(job: unknown): Promise<void> {
  const { data } = job as { data: { alertId: string; userId: string; type: string; severity: string } };
  // TODO: Send push notification based on alert type/severity
  // TODO: Notify emergency contacts if panic level
  // TODO: Emit realtime event via Redis pub/sub
  console.log('Processing alert fanout', data);
}
