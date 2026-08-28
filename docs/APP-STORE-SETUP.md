# App Store Connect — Bricky Pro In-App Purchase Setup

This guide covers configuring Bricky's monetization in **App Store Connect**:
creating the one-time **Bricky Pro** purchase.

> **Current status (verified):** App Store Connect has **no existing in-app
> purchases or subscriptions**. The old monthly/annual subscriptions only ever
> existed in the local `Bricky.storekit` test file and were **never created in
> App Store Connect**, so there is nothing to retire (Section B is N/A). The only
> task is to create the single non-consumable **Bricky Pro** in Section A.

## Background

Bricky Pro is a **single one-time (non-consumable) purchase — $4.99**. There is
no monthly or annual subscription. Cloud AI subject scanning is a hidden,
developer-only feature (unlocked via the in-app developer override) and is **not**
a purchasable product.

You **cannot convert** a subscription into a one-time purchase in App Store
Connect — they are different product types, each with their own permanent
product ID.

### Product IDs

| Product | Type | Product ID | Status |
|---|---|---|---|
| Bricky Pro | Non-Consumable | `com.bricky.app.pro` | **Create this** |
| Bricky Pro Monthly | Auto-Renewable Subscription | `com.bricky.app.pro.monthly` | N/A — never created in ASC |
| Bricky Pro Annual | Auto-Renewable Subscription | `com.bricky.app.pro.annual` | N/A — never created in ASC |

The product ID must match `AppConfig.iapProProductId` in the app
(`Bricky/App/AppConfig.swift`).

> **Note:** the local `Bricky.storekit` file is only for Xcode/simulator
> testing — it does **not** sync to App Store Connect. These steps configure the
> real products. Keep the product IDs identical in both places.

## A. Create the new one-time purchase ($4.99)

1. Sign in to **App Store Connect → My Apps → Bricky**.
2. In the left sidebar (Monetization area) click **In-App Purchases** → **Manage**
   (or the **+** next to *In-App Purchases*).
3. Click **Create** / **+**.
4. Choose type **Non-Consumable** → **Create**.
5. Fill in:
   - **Reference Name:** `Bricky Pro` (internal only, not shown to users).
   - **Product ID:** `com.bricky.app.pro` — must match `AppConfig.iapProProductId`
     exactly. ⚠️ This is permanent and can never be reused once created.
6. **Availability:** leave all countries/regions on (or pick a subset).
7. **Price Schedule:** click **Add Pricing** → select the **USD $4.99** price
   point → confirm. Apple auto-fills equivalent prices worldwide.
8. **App Store Localization:** add at least one (English) entry:
   - **Display Name:** `Bricky Pro`
   - **Description:** e.g. "Unlock unlimited scans, the full build library,
     3D & STL export, iCloud sync, and more."
9. **Review Information — Screenshot (required):** this must be a **real device
   screenshot** of the paywall at a valid iPhone/iPad resolution (e.g.
   1290×2796, 1284×2778, 1242×2688). **A 1024×1024 square is rejected here** —
   that size belongs to the *optional* promotional Image field, not this one.
   See [Section D](#d-review-screenshot-vs-promotional-image) below.
10. Add **Review Notes** (optional but helpful) describing the full Pro feature
    set for the reviewer.
11. Click **Save**. Status becomes **Ready to Submit**.
12. **Attach it to a version for first review:** open your app **version** page
    (the iOS version you're submitting) → scroll to **In-App Purchases and
    Subscriptions** → **+** → select `Bricky Pro`. First-time IAPs are reviewed
    alongside an app version.

## B. Retire the old subscriptions — N/A

**Nothing to do.** The Subscriptions section in App Store Connect is empty: the
monthly/annual products only ever existed in the local `Bricky.storekit` test
file and were never created in App Store Connect. Leave the Subscriptions section
empty and do **not** click *Create* there.

## C. Gotchas

- **Don't delete product IDs** expecting to reuse them — IDs are permanent and
  globally unique to your developer account.
- **No real subscribers?** If the app was never live (or these were never
  approved), retiring is instant and clean. If there *were* live subscribers,
  "Remove from Sale" is the correct move — never try to mass-refund or cancel them.
- **The new IAP must ship with a build** that references `com.bricky.app.pro`
  (the app already does). In **Sandbox**, test the purchase **and** *Restore
  Purchases* before submitting.
- **Tax/Banking:** if you've never sold a paid item, confirm **Agreements, Tax,
  and Banking** shows the **Paid Apps agreement = Active**. Otherwise IAPs won't
  load — StoreKit returns no products and the paywall shows "Plans are
  unavailable."

## D. Review Screenshot vs. Promotional Image

The IAP page has **two different image fields** with **different requirements** —
this trips people up:

| Field | Required? | What it is | Dimensions |
|---|---|---|---|
| **Screenshot** | **Required** | Review screenshot of the IAP inside the app | A **real device screenshot** size (e.g. 1290×2796, 1284×2778, 1242×2688). **NOT 1024×1024.** |
| **Image** | Optional | Promotional image for the App Store product page / offer & win-back codes | **Exactly 1024×1024**, PNG/JPG, 72 dpi, RGB, flattened, no rounded corners |

### Screenshot (required) — how to get a valid one
Upload an actual screenshot of the paywall from a device or simulator — those are
always valid sizes:
- **iOS Simulator:** run the app → open the paywall → **File ▸ Save Screen** (⌘S).
- **Real iPhone:** open the paywall → side + volume-up → AirDrop the PNG to your Mac.

A 1024×1024 square is **rejected** in this field ("The dimensions of one or more
screenshots are wrong").

### Image (optional) — the 1024×1024 mockup
A ready-made 1024×1024 mockup of the paywall lives at
[`docs/assets/app-store-iap-screenshot.html`](assets/app-store-iap-screenshot.html).
Open it in a browser at 100% zoom and screenshot **only the 1024×1024 square**
(exclude the drop shadow). Use it for the optional **Image** field, or skip the
Image field entirely — it's not required to submit.

## Related

- App code: `Bricky/App/AppConfig.swift` (`iapProProductId`),
  `Bricky/Services/SubscriptionManager.swift` (entitlement logic),
  `Bricky/Views/PaywallView.swift` (paywall UI).
- 1024×1024 promotional-image mockup: `docs/assets/app-store-iap-screenshot.html`.
- Local testing config: `Bricky.storekit`.
- Cloud AI (developer-only) proxy: `services/recognition-proxy/`.
