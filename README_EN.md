# Codex Switch

**One Codex environment. Several logins. A native Mac menu bar.**

[中文](README.md) · [Security](SECURITY.md) · [Architecture](docs/ARCHITECTURE.md) · [Validation](docs/VALIDATION.md)

macOS 13+ / Swift 5.9+ / SwiftUI / no package dependencies / MIT.

**0.2.1 is experimental.** It adds personal Google-account management for Antigravity CLI. All 104 automated tests pass. Native macOS build/install, recognizing and saving an existing real login, launching official agy, and refusing a switch while agy runs have been checked. A second-account login and real A → B → A switching still require manual acceptance. Antigravity 5h/weekly quota is read through official agy 1.1.11+ without model turns. See the validation record for boundaries.

![Interactive design preview with synthetic data, not a native Mac screenshot](docs/preview.png)

## Scope

Keep one existing `CODEX_HOME`, one config, and the same sessions, skills, and MCP settings. Save accounts in the macOS Keychain and choose the live login from a compact menu. Show remaining short/long quota, actual reset times, and credits/reset counts only when supplied by the official Codex app-server.

The app does not proxy requests, scrape browser cookies, handle API keys, implement OAuth token refresh, start model turns, redeem resets, or automatically rotate accounts. It launches your installed official Codex for browser login and active-account usage reads. Other accounts display timestamped **cached** usage rather than silently rotating their tokens.

**No unsafe hot swapping.** A running client may retain an in-memory identity. If Codex processes are detected, a requested switch waits until you close them, then expires after five minutes. No user process is killed. The menu shows the shared **file login**, not proof of every running client's identity. No promise of perpetual login validity or zero account-policy risk is made.

## Build and install

Install Apple development tools (`xcode-select --install`) and the official Codex CLI first. An existing Apple Development or Developer ID Application signing identity must be available in your Keychain. On first setup, list the available identities and explicitly pin the chosen certificate's full SHA-1 fingerprint:

```sh
python3 Scripts/configure-signing.py
python3 Scripts/configure-signing.py --identity CERTIFICATE_SHA1
```

Replace `CERTIFICATE_SHA1` with a fingerprint from the list. The tool does not select, create, or rotate certificates automatically. If none is available, configure a signing identity through Apple's developer tools first. Then install; later updates use the same command:

```sh
bash Scripts/install.sh
```

The installer checks the pinned identity, tests, builds the host architecture, signs with that identity, and installs `/Applications/Codex Switch.app`. It does not request passwords, `sudo`, or GitHub tokens; macOS may request permission to use the signing key. Quit an existing copy before updating. For just a build or both Mac architectures:

```sh
bash Scripts/build-app.sh
bash Scripts/build-app.sh --universal
```

Artifacts are locally signed, **not Apple notarized**. Never disable system-wide security to run them. A missing pinned identity stops the build instead of silently using ad-hoc signing. Explicit `--ad-hoc` builds are allowed only without a signing configuration, for CI or disposable tests; do not use them to update your everyday account manager.

The certificate fingerprint is stored outside the repository at `~/Library/Application Support/Codex Switch/signing/identity.json`. The private key remains in Keychain and is never bundled. Preserve that configuration and identity across updates. Each account saved by an older build may need one final **Always Allow** approval. Locked Keychains, prior one-time grants, or identity changes can still cause prompts. The setup does not broaden account ACLs, change system trust, or recreate saved records.

A fixed self-signed certificate is insufficient: modern macOS uses a changing code hash for its Keychain partition, whereas Apple-issued developer identities use a stable team identifier. See [Apple's Security source](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp#L259-L274).

## Onboarding

Close Codex processes. Open Accounts & Settings. The existing config needs a top-level `cli_auth_credentials_store = "file"`. When absent, the app can back up the config and prepend that one line, retaining every other byte. Existing `keyring`/`auto` settings require manual review and a fresh official login; no silent migration.

Save the current login. Name and add another account through the official browser flow. The new account stays active and the previous one is retained. An existing browser login is deduplicated without renaming its saved label. Click a row to switch; close any detected CLI, desktop, or IDE Codex backends when asked.

Usage reads use `initialize`, `account/read`, and `account/rateLimits/read` over local stdio. Automatic interval: five minutes. Manual throttle: fifteen seconds. Missing values remain unknown. The UI never assumes a passed reset means 100%, and never labels credits as currency. The linked web usage page uses the browser's separate login.

Default preferences: system language, masked email, active-account quota in the menu bar. English and Chinese are included, along with optional launch at login. Select a custom official CLI executable in settings if an nvm install cannot be found.

## Client scope

The primary target is the official CLI using shared file-based ChatGPT OAuth. Browser sessions, API keys, provider lists, proxy endpoints and enforced workspace policies are not changed. Stop other switchers. Desktop/IDE clients must actually honor this shared credential mode and be restarted; their specific versions have not been verified. The menu does not claim to inspect their in-memory identities.

## Storage and maintenance

Archived credentials are non-synchronizing ordinary macOS Keychain items under `cc.atou.codex-switchbar.credentials`. The official active `auth.json` is still a sensitive 0600 file. `~/Library/Application Support/Codex Switch` stores private account metadata, cached usage, and a recovery marker, not OAuth tokens. Workspace and user identity jointly identify an account. This avoids merging different users of one workspace.

Switching saves the current token, validates the target, journals the operation, rechecks processes and live bytes, and atomically replaces the login. Crash recovery reconciles with the current file instead of replaying a stale backup. The advisory lock only coordinates this app's instances; it cannot force official clients or other switchers to cooperate. Stop other switchers. Shared history is **not** work/personal data isolation.

A custom existing home can be set globally after quitting the app:

```sh
defaults write cc.atou.codex-switchbar codexHome -string "/absolute/path/to/existing/home"
```

No per-account homes are created. Symlink homes/credential files and ambiguous TOML layouts are rejected rather than guessed. Forgetting an account deletes only the saved copy; it does not sign out Codex or remove history.

```sh
swift test
python3 Scripts/check-source.py
```

The native app, domain core, and official-CLI protocol are separate modules. There is no Xcode project to synchronize or third-party dependency graph to update. See the architecture and validation documents before altering authentication behavior.

## Publication

No remote repository has been created by this source delivery. On a fresh extracted directory, with GitHub CLI installed and authenticated as `atou42`, run:

```sh
bash Scripts/publish.sh
```

This scans source, creates a **new public** `atou42/codex-switchbar`, and pushes an initial commit. Existing repositories and Git history are refused. The workflow then performs Mac testing and packaging; it does not deploy or publish a Release. Never paste credentials into chat, issues, or the repository.

Independently implemented. UI inspiration and official references are listed in [REFERENCES](docs/REFERENCES.md). Not affiliated with OpenAI.

## Terminal control

The installer adds `~/.local/bin/codex-switch`; include that directory in PATH. Commands: `start`, `stop`, `list`, `setup`, `save "Personal"`, `add "Work"`, `switch "Work"`, `status`, `cancel`, `usage`, `rename "Work" "Office"`, and `remove "Office"`. Add `--json` for structured output, or run `--help`.

Commands control the same menu-bar app and account store. Account commands launch it in the background if needed; `start` opens settings. `stop` and `status` do not launch a stopped app. Login and switching can be asynchronous: `login_pending`, `switch_queued`, and `working` are pending states, not completion. Use `status` to check the eventual result and active account. Immediate errors return a nonzero exit code. Adding requires Codex clients to be closed. Duplicate names require an exact account ID from `list`. Credentials are never returned.

The owner-only local socket checks both peers' user IDs. An occupied socket path is never automatically deleted, even after a crash; investigate the existing instance/state first.

## Device-code sign-in and compact menu bar

Choose Browser or Device code above the account name. Device mode shows a one-time code, Copy code, and the official verification-page button. CLI: `codex-switch add "Work" --device`, then `codex-switch status` for the code and URL; the default or `--browser` uses browser login. Device failure never silently falls back to browser login. Codes are held only in memory during login and cleared on completion/cancellation.

The menu bar shows only the icon and remaining percentage. Account names and details remain in the expanded panel. Hidden, missing, or stale quota produces an icon-only label.

## Antigravity CLI (0.2.0 experimental)

Choose **Antigravity CLI** in the settings window or menu panel. Its accounts and saved credentials are separate from Codex. The adapter supports the inspected personal Google (`consumer`) login format only. Enterprise/GCP/WIF and API-key modes are rejected. This is a local adapter, not an official Google account-switching API.

Save the current login first. To add another account, exit Antigravity clients, enter a name and choose **Add account & sign in**. Complete Google's sign-in in the official `agy` Terminal session, exit agy, then choose **Signed in — save account**. A switch requires clients to be closed. Launch agy again to use the selected account. There is no automatic rotation, force-quit, or custom OAuth refresh. The menu bar stacks 5h above weekly remaining percentages. Choose the independent Gemini or Claude/GPT group in the expanded panel. Missing/stale values display an em dash.

Use `codex-switch --provider antigravity` with `list`, `status`, `save [name]`, `add name`, `finish`, `switch name-or-ID`, `rename`, `remove`, `cancel`, `recover`, or `launch`. `start` opens this app's window; `launch` opens official agy in Terminal. `stop` quits the whole switcher. `usage` requests current-account quota; check `status --json` for the asynchronous result. `--device` fails explicitly for Antigravity. macOS may ask for permission to control Terminal.

Authentication copies stay in a separate Keychain service; metadata and token-free journals live under the app's `antigravity` support directory. Settings, conversations, and HOME are not cloned or rewritten. Partial native-storage updates retain a recovery marker and never automatically replay a stale backup. See [research and compatibility limits](docs/ANTIGRAVITY-RESEARCH.md) and [validation](docs/VALIDATION.md). A real two-account Google login/switch cycle remains a separate manual acceptance step.

The shared Antigravity Keychain item uses the same Apple-signed accessor as official agy, avoiding repeated cross-application permission requests when each login creates a new item. Private saved copies use the pinned app signing identity described above. No ACLs are broadened. Locked Keychains, one-time grants, old private account copies, and signing-identity changes can still require macOS approval.

### Saved weekly reset dates

Each account row shows its cached 7d balance, observation age and local reset date without switching accounts. Antigravity follows the selected quota group. Snapshots survive app restarts. Passed resets are marked as needing refresh; no automatic 100% balance or invented next reset is shown. This is cached observation, not live cross-device synchronization.
