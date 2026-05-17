# App Store Connect — Metadata Checklist

Fill this in before submission. Every box is a field App Store Connect requires.
Once filled, paste into the relevant ASC pages — keep this doc as the source of truth.

## App Information

- [ ] **App Name** (30 chars max, shown under icon):
  - draft: `Penguin Slide`
- [ ] **Subtitle** (30 chars max, beneath name in search):
  - draft:
- [ ] **Primary Category**: `Games`
- [ ] **Secondary Category**: `Games → Arcade` (or Action / Casual)
- [ ] **Content Rights**: do you own/license all content? Yes/No
- [ ] **Age Rating** (answer the questionnaire — for this game expect 4+):
  - Cartoon/Fantasy Violence: None
  - Realistic Violence: None
  - Sexual Content: None
  - Profanity: None
  - Alcohol/Tobacco/Drugs: None
  - Mature/Suggestive: None
  - Horror/Fear: None
  - Gambling/Contests: None
  - Unrestricted Web Access: No
  - Medical Info: No

## Pricing and Availability

- [ ] **Price tier**: Free / Tier N
- [ ] **Availability**: all territories / selected
- [ ] **Pre-order**: no

## App Privacy

Based on the codebase audit (no networking, no analytics, no third-party SDKs,
UserDefaults stays on-device): **Data Not Collected** across all categories.

- [ ] Confirm in ASC → App Privacy → "Data Not Collected"
- [ ] Privacy Policy URL (required even when collecting nothing):

## Version Information (per release)

- [ ] **What's New in This Version** (4000 chars, plain text):
- [ ] **Promotional Text** (170 chars, editable without resubmission):
- [ ] **Description** (4000 chars):
- [ ] **Keywords** (100 chars total, comma-separated, no spaces around commas):
  - draft: `penguin,slide,arcade,casual,tilt,icicle,winter,pixel,game,offline`
- [ ] **Support URL**:
- [ ] **Marketing URL** (optional):
- [ ] **Copyright** (e.g. `© 2026 <your name>`):

## Build

- [ ] CFBundleShortVersionString and CFBundleVersion bumped via `scripts/bump-version.sh`
- [ ] Archive built in Xcode → uploaded to ASC
- [ ] Build selected in the version's Build section

## Screenshots

Captured via `scripts/capture-screenshots.sh`. Required device sizes:

- [ ] **6.9" iPhone** (iPhone 16 Pro Max) — at least 1, max 10
- [ ] **6.5" iPhone** legacy slot (iPhone 15 Plus) — required if 6.9" supplied
- [ ] **13" iPad** (iPad Pro M4) — required because TARGETED_DEVICE_FAMILY includes iPad
- [ ] **12.9" iPad** legacy slot — required if 13" supplied

Landscape orientation (matches `UISupportedInterfaceOrientations`).

## App Preview Video (optional)

- [ ] 15-30 sec landscape MP4 per device size, no audio narration unless captioned

## Review Information

- [ ] **Sign-in required?** No
- [ ] **Demo account**: N/A
- [ ] **Contact info**: first name, last name, phone, email (for Apple's reviewer)
- [ ] **Notes**: include:
  - "Tilt controls: tilt device left/right to slide the penguin and dodge icicles."
  - "Game is fully offline — no network, no analytics, no third-party services."
  - "Locked to LandscapeLeft only."

## Export Compliance

- [ ] `ITSAppUsesNonExemptEncryption = false` in Info.plist (done — skips per-upload prompt)
- [ ] No annual self-classification report needed (no encryption beyond exempt iOS-standard)

## Pre-submission checks

- [ ] App icon visible in TestFlight build (sanity check before App Store)
- [ ] Launch screen shows SkyBackdrop (no black flash)
- [ ] PrivacyInfo.xcprivacy present in archive (Organizer → right-click → Generate Privacy Report → only UserDefaults / CA92.1 listed)
- [ ] Crash-free on at least one physical device + one iPad sim
- [ ] All deep links/URLs in this doc are live
