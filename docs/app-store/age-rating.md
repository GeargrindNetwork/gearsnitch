# Age Rating Rationale

## Recommendation: **17+**

Driver: peptide and supplement tracking maps to App Store Connect's **Medical/Treatment Information — Infrequent/Mild**, which pushes the rating from 12+ to 17+.

## App Store Connect questionnaire answers (proposed)

| Category | Answer | Reason |
|---|---|---|
| Cartoon or Fantasy Violence | None | |
| Realistic Violence | None | |
| Prolonged Graphic/Sadistic Realistic Violence | None | |
| Profanity or Crude Humor | None | |
| Mature/Suggestive Themes | None | |
| Horror/Fear Themes | None | |
| Medical/Treatment Information | **Infrequent/Mild** | Peptide + supplement log is user-authored journal, not treatment advice |
| Alcohol, Tobacco, or Drug Use or References | None | Supplements are OTC; we do not reference controlled substances |
| Simulated Gambling | None | Referral rewards are promotional credit, not real-money gambling |
| Sexual Content or Nudity | None | |
| Graphic Sexual Content and Nudity | None | |
| Contests | None | |
| Unrestricted Web Access | **Yes** (if in-app browser loads external privacy/support pages) | Confirm with founder whether SFSafariViewController counts |
| Gambling | None | |

## Fallback if 17+ is a business problem

- Remove peptide-specific language from on-device copy.
- Reframe as "supplement journal" only (drop peptide templates).
- Age rating drops to 12+ (still requires "Infrequent Medical" for supplement dosing reminders).
- **Do not do this without product sign-off** — it guts a core feature.

## Known rejection risk

Apps that frame dose tracking as "treatment guidance" get rejected under 5.1.3. Our copy must stay in journal / log territory. See `review-notes.md` §5.1.3.
