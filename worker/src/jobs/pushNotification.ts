export async function processPushNotification(job: unknown): Promise<void> {
  const { data } = job as { data: { userId: string; type: string; title: string; body: string } };
  // TODO: Fetch user's active APNs tokens
  // TODO: Send via APNs
  // TODO: Log delivery in notification_logs
  console.log('Processing push notification', data);
}
