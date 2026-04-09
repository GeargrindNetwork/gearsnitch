export async function processSubscriptionValidation(job: unknown): Promise<void> {
  const { data } = job as { data: { userId: string; receiptData: string } };
  // TODO: Validate Apple receipt with Apple servers
  // TODO: Update subscription status
  console.log('Processing subscription validation', data);
}
