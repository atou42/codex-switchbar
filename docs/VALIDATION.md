# Validation record — source preview 0.1.0

## Local Mac installation follow-up — 2026-09-19

On macOS 26.2 (Apple Silicon), using Apple Swift 6.3.3:

- `bash Scripts/install.sh` completed: all 50 tests passed, the native release app compiled, ad-hoc signing verification passed, and the app was installed in `~/Applications/Codex Switch.app`.
- The installed application process was confirmed running from that location.
- Native UI inspection could not be completed because the computer-use service timed out. No real account login, Keychain save, account switch, or quota query was performed as part of this check.
- Intel/universal compilation and the remaining acceptance scenarios are still pending.

The original Linux delivery record below is retained as historical evidence; its environment and publication statements describe that original delivery.

### Launch-window fix — 2026-09-19

The first installed build stayed running but reopening it did not show a window. Two native lifecycle regression tests reproduced the missing launch/reopen behavior before the fix. The app now owns one reusable settings window, opens it on launch and reopen, and shares its account model with the menu panel. All 52 tests passed after the fix. The rebuilt installed app's real “账号与设置” window was inspected through macOS accessibility; it showed the expected file-store setup prompt. No authentication setting was changed. Menu-bar placement and real account switching remain unverified.

Recorded 2026-09-19. This is an honest boundary between executed checks and work that requires a Mac/account. No real OpenAI credentials were available to or used by this build environment.

## Executed here

| Check | Environment | Result |
| --- | --- | --- |
| `swift test` | Swift 6.2.1, x86_64 Linux | **50 tests passed; 0 failures** |
| Swift macOS-branch syntax parsing | `swiftc -frontend -parse -target arm64-apple-macosx13.0` | App, core and icon-generator syntax passed; **not SDK type-checking** |
| Shell syntax | `bash -n` over build/install/publish scripts | Passed |
| Property-list parsing | Python `plistlib` | Passed |
| Workflow YAML parsing | Python YAML parser | Passed syntactically; workflow not run |
| Credential-pattern/source scan | `Scripts/check-source.py` | No matched known secret patterns or prohibited data files |
| Interactive HTML preview | Headless Chromium / Playwright | **13 scenario checks passed; no JavaScript errors** |
| Rendered preview inspection | Light, dark, and small-screen HTML rendering | Inspected, including dark text contrast and 390px overflow |

The code package has no external Swift dependencies. Tests use a memory vault, private temporary directories, synthetic JWT claims, and a local Python fake of the app-server protocol. **These are not live-service integration tests.** The test executable's Linux fallback is not a Mac app binary.

The exact test identifiers and browser scenarios are recorded in `validation-summary.json`.

## What the core tests cover

Credential schema rejection, raw-byte preservation, local identity extraction, separate users in one workspace, one user in different workspaces, deduplication and labels, correct handling when the browser reuses an existing account, fresh token snapshots, actual-file active detection, explicit unknown-account import, shared config/session preservation, safe removal without logout, vault failures, target identity mismatch, late/concurrent auth changes, process gates, recoverable journal behavior, no resurrection of deleted login, unsupported index schemas, stale usage-result rejection, configuration mode checks, byte-preserving opt-in, symlink rejection, file modes and compare checks, optional usage fields, multi-bucket response decoding, numeric credits, invalid reset dates, server errors without leaked payloads, early login notifications, timeout, cancellation, process-name parsing, and official-login URL allowlisting.

A test passing is evidence for that fixture/path, not proof of universal race freedom or provider-policy compliance.

## Not executed here

**No macOS SDK/compiler runtime is present.** Native AppKit/SwiftUI/Security.framework type-checking, linking and actual `.app` launch have not been performed. Neither have real Keychain prompts, ad-hoc signing behavior, launch-at-login approval, installed Codex login/token refresh, real usage RPC, or official desktop/IDE recognition. The supplied GitHub workflow has not been published or run by this delivery. No public repository has been created.

A native build can reveal SDK/type errors not caught by syntax parsing. A successful future CI build still will not replace an on-device OAuth/Keychain smoke test. Do not label this artifact a verified production release or distribute it as Apple-notarized.

## On-Mac acceptance checklist — still pending

Use an ordinary self-owned account and inspect the source first. Never put test secrets into this repository or CI.

- [ ] Run `swift test` and `bash Scripts/build-app.sh --universal` on a Mac. Confirm both architecture slices and bundle signing verification.
- [ ] Install in `~/Applications`, launch from Finder, and verify menu bar / settings / normal app exit on both light and dark appearances. Check popover fit on a small screen and when extra quota buckets expand.
- [ ] Save an already logged-in account. Confirm a Keychain item appears under the expected service and token bytes do not appear in the account index. Inspect initial/persisted file permissions.
- [ ] Exercise Keychain denial/locked login keychain, then approve the expected local app. Verify denial does not modify live auth. Inspect permission prompts after rebuilding the ad-hoc app.
- [ ] Add B through the official browser, verify B becomes active and A is retained. Cancel halfway and confirm the resulting live identity and saved copies remain coherent.
- [ ] Switch A → B → A with clients closed. Verify each newly launched official CLI reports the intended account. Compare config/history before and after. Do not post auth hashes or tokens publicly.
- [ ] Let official Codex refresh a token during ordinary use, close it, switch away/back, and confirm the latest token survives. Verify using a second device is not silently causing refresh-token conflicts.
- [ ] Start CLI, desktop and IDE backends separately. Request a switch; verify waiting, cancellation and five-minute expiry. Close backends and confirm completion. A paused task alone must not count as an exited process.
- [ ] Read actual quota. Compare active identity, window lengths, percent remaining, absolute reset date/time and optional credits with the official client. Verify unknown values, passed reset, network error and cached inactive accounts.
- [ ] Interrupt a operation in a controlled disposable test environment. Verify journal recovery reconciles the live login and never blindly restores a stale blob. Do not perform destructive crash experiments on irreplaceable credentials.
- [ ] Test custom official CLI paths (including nvm), supported shared-home selection, launch-at-login approval, logout/relogin and sleep/wake. Confirm the app starts no unintended user model turn.
- [ ] After creating the new repository yourself, confirm public contents contain only source/preview/synthetic tests and inspect the actual macOS Actions result.
