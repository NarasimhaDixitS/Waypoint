# Shipping an iOS app to the App Store — what actually goes wrong

Written from Waypoint's three rejections and the four causes caught before Apple found them.
None of it is theory: every item below either cost a review cycle or came within one step of
doing so. Kept outside `WaypointApp/` because it applies to the next app, not this one.

The short version, if you read nothing else:

> **Most rejections are not about your code.** Two of Waypoint's three were configuration —
> something created but never attached, something said in one place and contradicted in
> another. The one that *was* code was invisible to 253 passing tests, because it was about
> where a finger lands rather than what a function returns.

---

## The three rejections, and what each really was

### 1. "The app includes references to in-app purchases but the products have not been submitted" — 2.1(b)

Both subscription products sat at **Ready to Submit** with complete metadata, prices and
review screenshots. That is not submitted. **Creating a product in App Store Connect does
nothing on its own** — it has to be a line item *inside the version's review submission*,
which is a separate action on the version page.

This is the single easiest rejection to earn and the easiest to prevent. See the purchase
section below.

### 2. "Did not include the title of the product" — 3.1.2(c)

The paywall showed plan rows reading "Monthly" and "Annual". Those are *lengths*. Nothing on
the screen said "Waypoint Pro". Apple's disclosure list at the point of purchase is **four
things, not three**:

- the **title** of the product
- its **length** (for a subscription)
- its **price**
- working links to the **Terms of Use (EULA)** and the **privacy policy**

A source comment claiming the list had three items is what made this a blind spot for weeks.
Guideline 3.1.2 governs auto-renewable subscriptions specifically, so it stops applying if you
move to a one-time purchase — but keep naming the product and showing the links anyway.
Removing something a reviewer has already been shown invites the question of why.

### 3. "Subscription button was unresponsive" — 2.1(b)

The real bug, and worth the most attention because **nothing catches it**: not the compiler,
not the tests, not a screenshot, not a simulator.

In SwiftUI, `.buttonStyle(.plain)` hit-tests against **what the view draws**. A button whose
label is a transparent stack — a label, a `Spacer`, a chevron — is tappable on the glyphs and
nowhere else. The padding is dead. The gap the `Spacer` opens is dead. On a full-width row
that is most of the row, and the middle — the obvious place to tap — is the deadest part.

It looks perfect in a screenshot. It passes every test, because tests assert on state, not on
where a finger can land. The reviewer tapped the centre of the purchase row, nothing happened,
and that is an automatic rejection.

**The fix is `.contentShape(Rectangle())`.** Put it on a shared button style or row helper
rather than at call sites — a helper also covers the things that aren't buttons at all, like a
`NavigationLink` or a row wrapping a `Picker`, which no button style can reach.

**Audit for it like this:**

```bash
# every plain button, and whether the file declares a shape anywhere
for f in $(grep -rl 'buttonStyle(.plain)' Sources/); do
  echo "$(grep -c 'buttonStyle(.plain)' "$f") plain / $(grep -c 'contentShape' "$f") shape  $f"
done
```

A file with many plain buttons and no `contentShape` is where to look first. In Waypoint the
worst offender turned out to be the **tab bar** — explicit `frame(width:)`, no declared shape,
so only the 22pt icon was live and every gap between tabs did nothing. The most-used control
in the app, dead across most of its surface, for months.

---

## The four caught before Apple found them

These never reached a reviewer, but each would have cost a cycle.

**No territory availability on the purchase.** The product sat at `MISSING_METADATA` with every
visible field filled in. Availability is a *separate record*, not an attribute — and
`availableInAllTerritories` is not a valid create-time field. It needs its own call with an
explicit list of territories.

**Review notes that contradicted the app.** After pivoting from subscriptions to a one-time
purchase, the App Review notes still described renewal terms. A reviewer reading "renews
automatically" and then seeing a screen that says "one payment" draws exactly the wrong
conclusion. **Re-read the review notes every time what you sell changes.**

**Stale copy in locked states.** Four strings still told people to *subscribe* after the app
had stopped selling subscriptions. They were invisible because a gate message only renders
while locked, and development runs unlocked. They shipped to TestFlight under a store listing
promising a one-time purchase. Caught by a marketing screenshot, not by 253 tests.

> Grep string **literals** after any change to what you sell — not identifiers, which are
> legitimately full of words like `subscription`.

**A dead privacy policy URL.** Apple *fetches* that URL. A 404 is an automatic rejection, and
the support URL had been pointing at the privacy path. Open both links in a private window
before every submission.

---

## Pre-submission checklist

### Metadata that blocks submission

- [ ] **Primary category is set.** It lives on the `appInfo` object, beside name and subtitle —
      **not on the version**. A pre-flight that walks the version's own fields misses it
      completely. This blocked Waypoint at the very last step.
- [ ] **Privacy policy URL loads.** Open it. Apple fetches it.
- [ ] **Support URL loads, and is not the privacy URL.**
- [ ] **EULA link** in the App Description or the EULA field, for *every* localisation.
- [ ] **App Privacy answers match what actually ships.** Adding an analytics or purchases SDK
      changes the answer. Waypoint went from "Data Not Collected" to declaring Purchase History
      and Device ID the day RevenueCat landed.
- [ ] **Age rating** questionnaire complete.
- [ ] **Review notes describe the app you are actually submitting.**
- [ ] **Screenshots** are current. They cannot be edited while the version is
      `READY_FOR_REVIEW`, and there is a **hard cap of 10 per set** — a six-for-six swap has to
      interleave uploads and deletes.

### In-app purchases — where two of three rejections came from

- [ ] Product metadata complete: display name, description, price.
- [ ] **Review screenshot attached** to the product itself.
- [ ] **Availability record exists**, with territories.
- [ ] **The product is a line item inside the version's review submission.**
- [ ] On the summary page before submitting, **count the items**. You want the app version
      *and* each purchase. One item means the purchase is not coming with you.
- [ ] After submitting, the product's state should read `WAITING_FOR_REVIEW`. If it still says
      `READY_TO_SUBMIT`, **it was not included** — that is the positive confirmation worth
      checking, because "I ticked the box" is not evidence.

**Attaching a purchase is web-UI only.** The App Store Connect API accepts `appStoreVersion`,
custom product pages, app events and experiments as submission items, and returns
`409 ENTITY_ERROR.RELATIONSHIP.UNKNOWN` for a purchase. No automation can do this step or
verify it for you beforehand. Budget for a human.

### The build

- [ ] **Verify the exported IPA, never the `.xcarchive`.** The archive's `.app` is signed for
      development and carries `get-task-allow: true`; export re-signs it for distribution and
      flips it to false. Checking the archive reports problems that do not exist.

```bash
unzip -q export/YourApp.ipa -d /tmp/verify
APP=/tmp/verify/Payload/YourApp.app
codesign -dvvv "$APP" 2>&1 | grep -E "Authority=Apple Distribution|TeamIdentifier"
codesign -d --entitlements :- "$APP" | grep -A1 get-task-allow   # must be false
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist"
```

- [ ] **Debug launch flags and test affordances are stripped** from the release binary.
- [ ] **Bundle IDs match the provisioning profiles exactly.** The simulator never checks
      provisioning, which is why a mismatched app extension can work for months in development
      and never once on real hardware.
- [ ] Entitlements are per-target. A shared entitlements file makes an extension request
      capabilities its App ID lacks.

**Two traps when grepping a binary for strings:**

- `strings -F` misses anything containing an **em dash**. Use `strings -a`.
- Swift stores strings of **15 bytes or fewer inline** in the `String` struct rather than in
  the string table, so short literals are **invisible to `strings` entirely**. `"Goal complete"`
  is 13 bytes and cannot be found this way. Check a type name or a longer literal instead.

And remember it proves presence, never absence.

---

## How submission actually works

Plain mechanics, because several of these surprised us:

- **Uploading a build is not submitting it.** Upload freely. It touches no submission and
  starts no clock. TestFlight picks it up and puts it on your phone.
- **A rejected version stays editable.** You do **not** need a new version number. Attach a new
  build to the same version and go again — all listing metadata survives.
- **Attaching a new build pulls the version out of `REJECTED`** and back to
  `PREPARE_FOR_SUBMISSION`.
- **The submission container is reused.** Resubmitting after a rejection re-adds items to the
  *same* submission ID rather than creating a new one.
- **A version that is an item in an open or rejected submission cannot join another.**
  Cancelling frees it.
- **Removing the version item from a submission puts it in `DEVELOPER_REJECTED`** — withdrawn
  by you. That is also what makes screenshots editable again.
- **Resubmission goes back in the queue.** Often quicker because the reviewer has context.
  Never guaranteed.
- **Do not edit metadata while the version is in review.** Edits can bounce it back out.

### Two separate places to talk to Apple — don't confuse them

| | What it is |
|---|---|
| **App Review Notes** | A metadata field on the version. Travels with the submission. The reviewer reads it *while reviewing*. Editable via API. |
| **Resolution Center** | The message thread attached to a rejection. A conversation. **No API** — web UI only. |

After a rejection, the notes are the better place to explain a fix, because they are attached
to the thing being reviewed rather than to a closed thread.

**Writing notes after a rejection that works:** name the guideline and the exact complaint,
say plainly that it was real and is fixed, then give **numbered steps to the thing that
failed**. If a reviewer could not find or operate something, assume the next one won't either
unless you walk them to it.

---

## Testing purchases

- **Apple reviews purchases in the sandbox, and a product does not need prior approval to work
  during review.** So a product sitting at `READY_TO_SUBMIT` is *not* a cause of a purchase
  failing in review. Do not spend hours there, as we did.
- **The simulator cannot complete a purchase** — no App Store account. But it **can** fetch
  product metadata, so the real localised price renders and a simulator capture is valid as the
  review screenshot. A price that shows as a dash is a network failure, not a baseline.
- **TestFlight purchases run in the sandbox against your real Apple Account.** No sandbox
  tester record is created.
- **Sandbox testers cannot be created via the API** — `POST /v2/sandboxTesters` is 403, allowed
  operations are `GET_COLLECTION` and `UPDATE`. Web UI only.
- **Once you own something, you cannot easily un-own it on device.** RevenueCat keys off an
  anonymous app user ID in `UserDefaults`, so signing in as a different sandbox Apple Account
  changes nothing, and deleting the app loses your data without helping.

  **The lever is the dashboard:** entitlements are mapped server-side from purchased products,
  so detaching the bought product from the entitlement makes the receipt grant nothing and the
  lock returns. Force-quit afterwards — purchase state is cached on device for a few minutes,
  so backgrounding and returning hands back a stale answer. Reattach when done.

### If purchases fail in review, check in this order

1. **Paid Apps Agreement is Active.** Business section of App Store Connect. Only the Account
   Holder can accept it, and **it can lapse on its own** when Apple publishes updated terms —
   which means a purchase path that worked last week can be dead today with nothing changed.
2. **The purchase SDK's key is valid.** For StoreKit 2, a missing in-app purchase key means
   transactions are never recorded and buyers never get what they paid for.
3. **The entitlement maps to the product**, and the offering is current and carries it.
4. **Only then look at your code** — and when you do, look at hit testing before logic.

---

## Automation: what the API can and cannot do

Useful, with sharp edges. Shipping a build from the command line takes about five minutes.

**It cannot:**

- attach an in-app purchase to a review submission
- create sandbox testers
- set App Privacy answers, pricing, or territory availability
- read or post Resolution Center messages

**Sharp edges found the hard way:**

- `POST /v1/betaGroups/{id}/relationships/builds` **only links** a build to a group. It does
  **not** submit it for Beta App Review — that is a separate `POST /v1/betaAppReviewSubmissions`.
  The web UI's one button does both, so a build sits at `READY_FOR_BETA_SUBMISSION` looking
  stuck forever.
- Asset upload is reserve → PUT → commit, and **the presigned PUT must not carry the
  `Authorization` header**, or object storage 400s.
- Re-adding a version whose assets are still `UPLOAD_COMPLETE` returns 409. Poll to `COMPLETE`.
- A build can take far longer to appear than usual. "Upload succeeded" and "build exists" are
  different events, sometimes twenty minutes apart. If it never appears, **Apple emails you** —
  that failure is not exposed in the API.

---

## The habits that would have prevented most of this

1. **Check the positive signal, not the action.** "I ticked the box" is not evidence. "The
   product now reads `WAITING_FOR_REVIEW`" is.
2. **After changing what you sell, re-read everything that describes it** — gate messages,
   paywall copy, store description, review notes. They live in four places and drift silently.
3. **Look at your own marketing screenshots.** A stale string shipped to TestFlight and was
   found by someone capturing a locked screen, not by the test suite.
4. **Tap the middle of things.** Tests assert on state; reviewers use fingers. Hand the build
   to someone who has not seen it and watch where they tap.
5. **Keep a file like this one.** Every item here cost something to learn once.
