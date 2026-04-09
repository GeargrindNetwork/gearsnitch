export async function processReferralQualification(job: unknown): Promise<void> {
  const { data } = job as { data: { referralId: string; userId: string } };
  // TODO: Validate referred user's subscription purchase
  // TODO: Update referral status to 'qualified'
  // TODO: Enqueue referral-reward job
  console.log('Processing referral qualification', data);
}
