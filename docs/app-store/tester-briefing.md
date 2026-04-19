# TestFlight Internal Tester Briefing

**You are one of our first testers. Please read this before opening the build.**

## What we're launching

GearSnitch is a fitness + gear + health log app for athletes. It connects to Bluetooth equipment, tracks workouts and runs, streams live heart rate (iPhone + Apple Watch), and logs supplements/peptides and labs in a private journal.

## Your mission in priority order

### 1. Sign up and onboard — 10 minutes

- Create account with a real email (receipts land there).
- Grant HealthKit, Location, Bluetooth, Notifications permissions when asked.
- Go through every onboarding step. Tell us if any step feels repetitive, unclear, or slow.

### 2. Pair one Bluetooth device — 5 minutes

- Use any BLE-capable gear (HR strap, scale, smart dumbbell).
- Try disconnecting and reconnecting 3 times.
- **Report:** pairing time, UI feedback during discovery, any "stuck" states.

### 3. Complete one workout — 15 minutes

- Start a strength workout OR a run.
- Watch live HR. If you have a chest strap AND an Apple Watch, check split HR.
- Save the workout.
- Verify it appears in your workout history.

### 4. Log a supplement or peptide — 2 minutes

- Open medication log.
- Add an entry with dose + time.
- Set a reminder.
- **Confirm:** reminder fires on time.

### 5. Explore the store — 2 minutes

- Add an item to cart. Don't check out (unless founder gives go-ahead).
- Try the referral QR code.

### 6. Try the Apple Watch companion — 5 minutes

- Launch the Watch app.
- Start a session from the Watch.
- Confirm HR shows on both devices.

## What we want you to break

- Bad network: turn Wi-Fi off mid-workout.
- Background: lock the phone for 10 min during a run.
- Permission denial: deny HealthKit and see what happens.
- Sign-out then sign-in; verify data reappears.
- Cancel a subscription trial (if you start one).

## How to send feedback

1. **In-app:** Settings > Send Feedback (attaches logs automatically).
2. **TestFlight:** screenshot + long-press > "Share Beta Feedback".
3. **Email:** beta@gearsnitch.com with steps to reproduce.
4. **Urgent crash:** iMessage the founder directly.

## Crash reporting

- TestFlight automatically ships crash reports. You do not need to file them manually.
- If you can trigger a crash on demand, please write down the steps and send to beta@gearsnitch.com.

## What NOT to do

- Do not post screenshots of unreleased features publicly.
- Do not share the TestFlight link outside the invited group.
- Do not use your real medical data if you're not comfortable (use test values).

## Known issues (as of this build)

- _Founder fills in before each TestFlight push._
- _Include JIRA / GitHub issue links._

## Timeline

- Feedback window: 72 hours from build invite.
- Retest window after fixes: 48 hours.
- Submit to App Review target date: _founder fills in._

Thank you. Your feedback is what makes this launch work.
