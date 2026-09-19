# Changelog

## 0.1.0 — 2026-09-19

Initial source preview. Native menu bar and settings; single shared Codex home; saved accounts in Keychain; identity-aware token snapshots; explicit queued switching; recovery markers; official app-server login and usage; optional credits/reset counts; truthful cache/reset states; English/Chinese, email masking and launch at login. Fifty synthetic-fixture core tests, source checks, build/install/publication scripts, and Mac CI are included.

Not a notarized or Mac-verified release. Native compilation, Keychain, live OAuth and on-device UI acceptance remain to be performed. A browser design preview is included and explicitly labeled as synthetic.
# Unreleased

- Add an explicit browser/device-code login choice in settings and `add NAME --device` in the CLI, with transient code/verification URL shown by status.
- Compact menu-bar label to icon + percentage; remove account names from the bar.
- Fix CLI background launch when invoked by its PATH name rather than absolute path.

- Add `codex-switch` CLI for app start/stop, status, account list/setup/save/add/switch/rename/remove, cancellation and usage refresh. Includes explicit pending states, `--json`, and same-user local control.

- Show the account/settings window on launch and when reopening the app, so access does not depend on finding the menu-bar item. Reuse the same window and account state from the menu.
- Add two macOS launch/reopen regression tests.
- Show a Dock icon while settings is open. Closing settings removes the Dock icon while keeping the menu-bar app running; reopening settings restores the Dock icon.
- Install into /Applications so the app appears in Finder's Applications folder. Clarify first-time setup, required account names, adding multiple accounts, and reopening after quitting.
- Fix official Codex 0.155.0 startup by replacing the removed `untrusted` approval option with `never`, retaining the read-only sandbox and account-only requests.
