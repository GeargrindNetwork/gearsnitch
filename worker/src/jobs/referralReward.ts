export async function processReferralReward(job: unknown): Promise<void> {
  const { data } = job as { data: { referralId: string; referrerUserId: string } };
  // TODO: Grant 90-day extension to referrer (idempotent)
  // TODO: Update referral status to 'rewarded'
  // TODO: Send push notification to referrer
  console.log('Processing referral reward', data);
}
