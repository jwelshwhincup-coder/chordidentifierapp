# Chord ID: first launch, paywalls, app icon, review prompt

You are working in the existing Chord ID iOS app (SwiftUI). The app already
works: tap or mic chord naming, strum playback, library, tuning and capo
pickers. This brief adds five things. Do them in the order below.

## How to work

- Before changing anything, read the code and tell me what already exists for
  each step (launch screen, onboarding, purchases, app icon, review prompt).
  Build on what's there. Don't duplicate or rewrite working code.
- One step at a time. After each step: stop, tell me what changed, tell me
  exactly how to test it on my phone, and wait for me to say continue.
- Ask your questions for a step together, before you start that step.
- I'm new to iOS development. Explain anything I have to do in Xcode or App
  Store Connect click by click.
- Never say something works unless you built it and ran the tests. Say plainly
  what you could not verify.
- Commit at the end of each step with a clear message and push.
- Don't change anything this brief doesn't ask for.

## What's in this folder

- `first-launch/01-launch-logo.png`: the logo screen
- `first-launch/02` to `05`: the four demo steps
- `paywalls/01-paywall-library-full.png`: shown on the 4th save
- `paywalls/02-paywall-tuning.png`: shown when picking a paid tuning
- `paywalls/03-paywall-capo.png`: shown when using the capo
- `logo/app-icon-1024-square.png`: the app icon, square, no transparency
- `logo/logo-rounded.svg` and `logo-rounded-1024.png`: the logo for use
  inside the app

The PNG mockups were rendered with a substitute font. Follow them for layout,
wording, colours and spacing, but use the app's existing font, colours and
component styles. Where a mockup and the real app disagree about how the app
looks behind a sheet or overlay, the real app wins.

## Logging in Linear

Log this work in Linear using the Linear tools connected to this session.

- First ask me which Linear team and project to use.
- Create one parent issue for this brief and one sub-issue per step below.
- When you start a step, move its issue to In Progress.
- When you finish a step, add a comment with: what changed, the files
  touched, how to test it, the commit hash, and anything you couldn't verify.
- Move an issue to Done only after I confirm I've tested it.
- Log any bug or follow-up you notice as its own issue; don't fix it unasked.
- If no Linear tools are available in this session, stop and tell me. Don't
  skip the logging silently.

## Step 1: App icon

- Set `logo/app-icon-1024-square.png` as the app icon in the asset catalog
  (single 1024 px source).
- Confirm it has no transparency and no pre-rounded corners. iOS rounds it.
- Ask me whether I want dark and tinted icon variants; if yes, propose them.
- Add `logo/logo-rounded.svg` to the asset catalog as an in-app image for
  the logo screen.

## Step 2: Logo screen

- On first launch, show the logo centred on the app background with
  "Chord ID" under it, as in `01-launch-logo.png`, then cross-fade into the
  app.
- Animate it over about 1.2 seconds: fretboard lines draw in, the question
  mark strokes on, the blue dot drops in with a small spring and a light
  haptic.
- Make the static iOS launch screen match the first frame so nothing jumps.
- On later launches use a quick fade only (ask me if I'd prefer the full
  animation every time).
- With Reduce Motion on, show the logo still and fade.

## Step 3: First-launch demo

Runs once, right after the logo screen. See mockups 02 to 05.

- Run it on top of the real Chord ID screen, not separate slides: dim the
  screen, cut a spotlight around the thing being explained, and show a white
  speech bubble with a pointer aimed at it.
- Show a tap ring where a finger would tap, then let the real UI respond
  using scripted input: dots spring in, the chord name appears. The demo
  builds a C major (x 3 2 0 1 0).
- Do not use the real microphone and do not ask for microphone permission
  during the demo. Step 4 shows the listening screen with scripted state.
- Steps and wording. Check each line against how the app really behaves and
  show me any you want to change before building:
  1. Spotlight a fret. "Tap any fret to place a finger." / "Tap it again to
     take it off."
  2. Spotlight the row above the nut. "Tap above a string to switch it." /
     "A circle means it rings open. A cross means it's muted or not played."
  3. Spotlight the chord name and the Strum and Save buttons. "The chord
     name appears straight away." / "Strum to hear it. Save to keep it."
  4. Spotlight the mic button. "Or tap the mic and play each string." /
     "Go low to high. Tap Skip string for any you don't play." with a
     "Start playing" button.
- Each bubble shows progress dots and "n of 4 · tap to continue". A tap
  anywhere advances. Steps also auto-advance after their animation.
- A "Skip" button is visible top right on every step.
- Motion: the spotlight slides between targets, bubbles spring in and fade
  out, the tap ring pulses before the UI reacts. Light haptic per step.
- When the demo ends or is skipped, clear everything it placed so the user
  starts with an empty fretboard.
- Remember it has been seen so it never auto-plays again. Add "Replay demo"
  in Settings.
- Support Reduce Motion, Dynamic Type and VoiceOver (each bubble is read
  aloud and Skip is reachable).

## Step 4: Paid upgrade and the three paywalls

One purchase unlocks everything. Tell me first what purchase code exists.

- Free: name chords by tap and by mic, strum playback, standard tuning,
  up to 3 saved chords.
- Pro: unlimited saved chords, all alternate tunings, custom tunings, capo.
- One non-consumable in-app purchase using StoreKit 2. No subscription, no
  account. My intended price is £4.99; always display the localised price
  from StoreKit, never a hard-coded one.
- Three sheets, each matching its mockup:
  - **Library full** (`01`): when a free user tries to save a 4th chord.
    Headline names the chord they're saving. The tiles show the names of
    their three saved chords and a locked fourth tile for the new one.
  - **Tuning** (`02`): when a free user picks any tuning except Standard.
    Headline names the tuning they tapped, and that tuning's tile is the
    highlighted one.
  - **Capo** (`03`): when a free user tries to set a capo.
- All three share the Free vs Pro table, with the feature they tapped as the
  first row, the blue button with the price and chevron, "Pay once. Yours
  forever. No subscription.", and "Restore purchase".
- Closing a sheet returns the user to where they were with nothing changed.
- After a successful purchase: dismiss the sheet, complete the action they
  were attempting (save the chord, apply the tuning, set the capo), and
  give a success haptic.
- Show a small lock on paid tunings and on the capo control for free users.
- Never delete or lock chords a user has already saved.
- The unlock must survive reinstalling and work offline after first check.
- Add a StoreKit configuration file so I can test purchases in Xcode, then
  walk me through creating the product in App Store Connect and testing
  with a sandbox account.
- No timers, countdowns, fake discounts or paywall on app open.

## Step 5: Apple's review prompt

Use Apple's built-in rating prompt (StoreKit `requestReview`). Ask at the
best moment in the app: just after the microphone has correctly named a
chord the user played.

- Trigger: the user's 3rd successful microphone identification ever. Wait
  until the chord-name animation and success haptic have finished, about
  1.2 seconds, then request the review.
- Only when the moment is clean. Skip it if, in this session, the user has
  seen the demo, closed a paywall, hit a "couldn't hear that" retry, or
  cleared the result straight after it appeared.
- If it was skipped, try again at the next clean success. Also try again at
  the 10th and 25th successes. Never more than once per app version.
- Apple decides whether the prompt appears and limits how often. Don't add
  my own "Do you like the app?" screen in front of it.
- Explain to me how the prompt behaves in a debug build and in TestFlight,
  so I know what to expect when testing.
- Add a "Rate Chord ID" row in Settings that opens the App Store review
  page. Ask me for the App Store ID when you need it.
- Keep the counters in one small, testable place, with a debug-only way to
  reset them.

## Step 6: Wrap up

- Run all tests. List what you could not verify without a real device.
- Give me a checklist of everything to test on my phone before I submit.
- Update Linear so every issue reflects its real state.

Start by reading the project and telling me what exists for each step, then
ask your questions for Step 1.
