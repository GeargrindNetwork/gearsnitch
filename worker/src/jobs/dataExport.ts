export async function processDataExport(job: unknown): Promise<void> {
  const { data } = job as { data: { userId: string; requestId: string } };
  // TODO: Collect all user data, generate export, notify user
  console.log('Processing data export', data);
}
