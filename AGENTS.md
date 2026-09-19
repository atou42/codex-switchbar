# Maintenance guide

Read README.md, SECURITY.md, and docs/ARCHITECTURE.md before touching authentication.

This is a single-home native Mac credential switcher. Preserve these invariants:

- No per-account CODEX_HOME, config, history, or skills. Switching changes only the live credential file.
- The file identity, not a selected UI flag, determines the active account. Workspace + principal jointly identify it.
- Saved secrets belong in the macOS Keychain; never serialize them into accounts.json, diagnostics, fixtures, preview, or issues.
- Save the newest live token before switching out. Keep unknown JSON fields byte-for-byte. No custom refresh, token injection, cookie scraping, or OAuth proxy.
- Refuse/queue while clients run. The process scan is best-effort, not a global lock. No force-switch or user-process kill.
- Journal operations and reconcile the actual current file after interruption. Never automatically replay a stale backup.
- Official account/login/usage RPC only; no model turns or quota-reset redemption. Other accounts show dated cache, not live invented balances.
- Unknown usage is unknown. Used percent is not remaining percent. A reset timestamp passing is not evidence of a fresh 100% balance.
- Preserve user config bytes except explicit, backed-up, one-time file-store opt-in. Ambiguous configuration fails closed.
- Public publication must contain source and synthetic fixtures only. Never publish local credentials or unrelated Git history.

Commands:

```sh
swift test
python3 Scripts/check-source.py
bash Scripts/build-app.sh --universal  # macOS only
```

Linux core tests do not validate SwiftUI, real Keychain, login items, signing, or live OAuth.
Do not update VALIDATION.md to say those passed without actually exercising them.
The HTML preview is separate demonstration code with synthetic data, not the production UI.
New functionality should live in the smallest existing module, with focused tests for failure paths.
