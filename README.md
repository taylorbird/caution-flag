# Cool-Down

A macOS menu bar app that notices when a Slack draft is running hot and gently checks in before you send it. All analysis is local. Nothing you type leaves your Mac.

- **Warm (score 4–6):** the menu bar leaf turns yellow and a small pill appears above the message box. It fades on its own.
- **Hot (7+):** the leaf turns red and a panel shows why, a calmer rewrite with a Copy button, your own note to yourself, and three choices: **Take 5** (a breathing timer), **Save draft for later**, or **I'm fine, dismiss**.

Requires macOS 15+. Apple's on-device model needs macOS 26+ with Apple Intelligence on; otherwise use Ollama.

## Build and run

```sh
brew install xcodegen          # once
scripts/build.sh --run         # builds Release, installs to ~/Applications/Cooldown.app, launches it
```

The project is generated from `project.yml`, so don't edit `Cooldown.xcodeproj` by hand. It's signed with your Apple Development identity (team `UFCDGSKCXB`) so the Accessibility grant survives rebuilds. With ad-hoc signing, macOS would forget the grant every build.

Tests and the sample harness live in the core package:

```sh
swift test --package-path Packages/CooldownCore
swift run  --package-path Packages/CooldownCore cooldown-harness            # heuristics only
swift run  --package-path Packages/CooldownCore cooldown-harness --apple    # + Apple model
swift run  --package-path Packages/CooldownCore cooldown-harness --ollama --model qwen2.5:3b
swift run  --package-path Packages/CooldownCore cooldown-harness --apple --text "per my last message…"
```

To check the panels without Slack: `~/Applications/Cooldown.app/Contents/MacOS/Cooldown -demo hot` (or `warm`, `breathing`, `onboarding`, `settings`).

## Permissions

Cool-Down needs **Accessibility** access so it can read the focused text field in apps you've chosen. The first launch opens a setup guide:

1. Click **Open Accessibility Settings**.
2. Find **Cooldown** in System Settings › Privacy & Security › Accessibility and switch it on.
3. The guide's checkmark turns green within a second.

If it's switched on but not detected (usually after moving or re-signing the app), remove it with **–**, then add `~/Applications/Cooldown.app` again.

Slack is an Electron app, so Cool-Down sets `AXManualAccessibility` on it to make Chromium expose its accessibility tree. To find the composer, it tries the app's focused element, then the system-wide one, then descendants of a focused wrapper group, then the last composer it found. As a last resort, and at most once every 2 s, it does a bounded search of the window. Password and secure fields are skipped.

"Clear it from the message box" (offered only after you save a draft) first tries an Accessibility write. If Slack ignores that, it sends ⌘A then Delete to Slack.

## Tone models

Settings › Model offers **Automatic** (Apple, then Ollama), **Apple**, **Ollama**, or **Quick checks only**.

Quick checks always run first: all caps, `!!`/`?!`, profanity and insults, "always"/"never", blame phrases ("how many times", "your fault"), passive-aggressive phrases ("per my last message", "as I already said"), and sarcasm markers. They lift the model's score but never lower it. A very short draft (≤30 characters) with no signals skips the model.

The model is asked for JSON with `heat` 0–10, `category` and a one-sentence `reason`. Apple's model uses guided generation (`@Generable`) with a prewarmed session. Ollama uses its structured-output `format` schema, and the parser tolerates code fences, prose, stringified numbers and odd category spellings. The calmer rewrite is a separate, plain-text call made only when the red panel opens, and it fills in place.

Timing: the text field is checked every 0.25 s. Quick checks show a nudge about 0.8 s after you stop typing. The Apple model's score follows in about 1.5 s, and a rewrite in another 0.4–0.9 s. If Apple's safety layer declines the text, it's treated as at least warm.

Context: once two drafts in 20 minutes have run warm or hotter, scores get +1 until things settle.

### Setting up Ollama

```sh
brew install ollama
ollama serve &                 # or launch the Ollama app
ollama pull llama3.2:3b        # or qwen2.5:3b
```

Then go to Settings › Model › Ollama and click **Test connection**. The first request after a restart takes several seconds while the model loads; Cool-Down asks Ollama to keep it warm for 30 minutes.

## Privacy model

- Text is read only from apps you've switched on, and only while that app is in front.
- Analysis runs on-device: Apple's model, or Ollama at a **loopback** address. `LoopbackGuard` rejects any other host in code, and that check is unit-tested.
- Draft text lives in memory only. It isn't logged, persisted or sent anywhere. Logs (`log stream --predicate 'subsystem == "com.tbird.cooldown"'`) contain scores and levels only.
- The one exception: **Save draft for later** writes that draft to `~/Library/Application Support/Cooldown/drafts.json` (mode 600). You can delete drafts from the menu bar › Saved Drafts.
- Settings (sensitivity, watched apps, quiet hours, your personal note) live in UserDefaults.

## Layout

```
Packages/CooldownCore/    pure logic, unit-tested
  HeuristicScorer         cheap pre-checks
  ToneResponseParser      lenient model-JSON parsing
  ScoreCombiner           model + heuristics + sensitivity + recent context → level
  ToneAnalyzer            protocol; FoundationModelsToneAnalyzer, OllamaToneAnalyzer
  SampleMessages          calm / heated / subtle fixtures (tests + harness)
App/Sources/
  Capture/                TextCaptureService (AX polling every 250 ms on a background queue; focused app read via AX)
  Analysis/               DraftCoordinator (0.8 s debounce, immediate every +280 chars, instant heuristic nudge), AnalyzerProvider
  Interventions/          InterventionController, non-activating NSPanels, pill/panel/breathing views
  Settings/               SettingsStore, DraftStore
  Windows/                onboarding, settings, saved drafts
```

## Roadmap

Built (MVP): Slack capture, Apple + Ollama analysis, heuristics, warm/hot nudges, rewrites, Take 5, saved drafts, sensitivity, watched apps, quiet hours, snooze, personal note, launch at login, onboarding.

Next: cooling-off mode (a scoped event tap on Return in the watched app, with a 60-second wait or deliberate confirmation, easy to toggle off), and the opt-in local weekly stats (nudges and pauses; scores and timestamps only).
