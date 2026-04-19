# App Review Notes

**Purpose:** Pre-written responses to the most common rejection triggers for GearSnitch. These go into the App Review "Notes" field at submission time, and serve as templated responses if App Review pushes back.

Also includes a **demo account** section — Apple requires a working login for review.

---

## Demo account (required field)

```
Email:    appreview@gearsnitch.com
Password: <founder sets, stored in 1Password: "App Review Demo">
```

- Account has all HealthKit permissions pre-granted (simulated).
- Has a paired mock BLE device (synthetic HR stream).
- Has an active subscription in sandbox.
- Has a medication log with 3 sample entries.

## Contact

- **First name / last name:** _founder_
- **Phone:** _founder_
- **Email:** founder@gearsnitch.com (monitored during review window)

---

## Guideline responses

### 3.1.1 — In-App Purchase

> "Apps offering services that are consumed outside of the app (specifically physical goods or services) can use other payment mechanisms. Digital content that is used within the app must use IAP."

**Our position:**
- All **digital content** (GearSnitch Pro subscription, analytics upgrades) is sold via StoreKit IAP. We do not route digital purchases through Stripe inside the app.
- All **physical goods** (apparel, straps in our store) are sold via Stripe Checkout — Apple's rules explicitly exempt physical goods.
- **Referral rewards** are store credit for physical goods only. They are never redeemable for digital content.
- **Stripe Customer Portal** is accessible only on web (`gearsnitch.com/billing`) and is linked from Settings with the External Link Entitlement. We do not link to it from the paywall screen itself.

### 5.1.1 — Data Collection and Storage

> "Apps should only request access to data relevant to the core functionality of the app."

**Our position:**
- **HealthKit read:** heart rate, active energy, workouts, body mass. **Write:** workouts we save.
- Each Info.plist usage description is feature-specific (e.g., `NSHealthShareUsageDescription` references heart rate streaming, not "general health").
- No third-party SDKs receive health data.
- Data at rest is encrypted via iOS data protection APIs (Complete protection class). _Caveat: full at-rest encryption audit tracked in S5 and completes before 1.0._
- User can delete all data from Settings > Account > Delete Account.

### 5.1.3 — Health/Medical

> "Apps conducting health-related human subject research must obtain consent… Apps providing diagnosis, treatment advice, or dosing should expect additional scrutiny."

**Our position:**
- The peptide/supplement log is a **user-authored journal**.
- GearSnitch does **not** diagnose.
- GearSnitch does **not** recommend doses. The dosing calculator is a **unit converter** (mg ↔ IU ↔ mL) — it does not suggest what to take.
- GearSnitch does **not** claim any therapeutic benefit.
- In-app disclaimer appears before first use of the log: "This is a journal. Consult your physician for medical advice."

### 4.0 — Design

> "Apps should be designed for ease of use."

**Our position:**
- 3+ tabs because we span three distinct domains (fitness, health log, store). Combining them into one tab would bury features users look for by name.
- Split heart rate is core to our value proposition — two concurrent streams is the feature, not an accidental duplication.

### 2.3.1 — Accurate Metadata

> "Make sure your app description, screenshots, and previews accurately reflect the app's core experience."

**Our position:**
- Every advertised feature (BLE pairing, split HR, Watch, peptide log, gym geofence, referrals, store) is implemented and reachable from the first screen.
- Screenshots are sourced from the live app with demo data only.
- No coming-soon features are shown.

### Family Sharing

- **Shared:** GearSnitch Pro subscription (Apple Family Sharing enabled on StoreKit product).
- **Not shared:** personal health log, paired devices, saved workouts, store orders, referral credit — these are per-Apple-ID.
- We disclose this in the subscription screen fine print.

---

## Export compliance

- App uses HTTPS (TLS) only.
- Qualifies for **Annotation 5** exemption under Category 5 Part 2 (encryption for standard HTTPS, not proprietary crypto).
- Answer on App Store Connect: "Yes" to "Does your app use encryption?" → "Yes" to "Does it qualify for any exemptions?" → "Exempt under category (b)(1)".

---

## If App Review pushes back

1. Don't panic. Read their message carefully.
2. Post the rejection text in Slack #launch.
3. Founder drafts the response using the relevant section above.
4. Reply via Resolution Center within 24 hours — faster responses move to the top of the queue.
5. If they escalate, request a phone review (option appears after 2 back-and-forth rejections).
