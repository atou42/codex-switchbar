# Antigravity CLI adapter research

Research date: 2026-09-20. This adapter targets the official Google `agy` CLI,
not third-party projects named Antigravity CLI and not browser-cookie sessions.

## Public contract

- [Official installation and authentication](https://antigravity.google/docs/cli/install)
  documents native system-keyring login, automatic browser login when no saved
  session exists, and manual authorization-code entry in SSH sessions.
- [Official repository](https://github.com/google-antigravity/antigravity-cli)
  documents the same authentication model. `/logout` clears saved credentials;
  it is not an account-profile switch command.
- The installed `agy --help` exposes no account-profile list/select/login
  subcommand. The app therefore launches the official interactive CLI for new
  login and requires an explicit completion step. It does not send model prompts,
  implement OAuth, intercept callbacks, or refresh tokens itself.

## Locally verified storage layout

Inspection was read-only. No official credentials were modified during research.
Secret values were read only in memory to compare structure and identity; none
are included here, in test fixtures, or in command output.

- The macOS generic-password item has service `gemini` and account `antigravity`.
- Its password bytes are `go-keyring-base64:` followed by base64-encoded JSON.
  This is the encoding used by the official binary's `go-keyring` library.
- The official file copy is `~/.gemini/antigravity-cli/antigravity-oauth-token`.
  It is JSON with mode 0600.
- Both copies contained `token` (`access_token`, `refresh_token`, `token_type`,
  `expiry`), `auth_method: consumer`, and `id_token`. The ID-token payload contains
  the Google `sub` and email used for local account identification only.
- The Keychain and file had the same identity and refresh-token lineage but
  different access-token expiries: the Keychain was newer. A file-only adapter
  would save stale credentials. The primary Keychain copy is authoritative;
  file fallback is accepted only when the Keychain item does not exist.
- No Keychain timeout marker existed during inspection. Binary inspection of
  `NewCLITokenStorage` showed a composite Keychain/file implementation with
  marker `cache/antigravity-keyring-unavailable`. The adapter refuses operation
  when this marker exists and never removes it or forces file mode.
- `GEMINI_FORCE_FILE_STORAGE` was absent from the local environment and was not
  found in the installed binary. The adapter does not rely on that variable.
- The binary's stored-token structure also supports `user_tier`, `project_id`,
  `region`, and `wif_provider`. Enterprise/GCP/WIF modes are outside this initial
  adapter. Unknown JSON fields remain in the opaque stored blob.

## Adapter safety and compatibility limits

This storage format is observed implementation detail, not a documented stable
account-management API. Future CLI versions may change it. Missing required
fields, malformed JSON, conflicting identities between copies, unsupported
provider settings, unsafe paths, and Keychain errors fail explicitly.

The shared official Keychain item is accessed through `/usr/bin/security`, the
same Apple-signed accessor used by [go-keyring's Darwin backend](https://github.com/zalando/go-keyring/blob/master/keyring_darwin.go).
Officially created items trust this accessor. Previously the app accessed the
item under its own identity, so each new login's newly created item requested
another cross-application authorization. Reusing the official accessor removes
that extra identity without changing any ACL or unlocking the Keychain.

Writes use `security -i` with a fixed service/account and a canonical base64
value sent through stdin, never secret process arguments. The command matches
upstream's 4096-byte interactive limit; oversized data fails before mutation.
Diagnostics are discarded because interactive commands can echo secrets. Reads
are bounded; missing-item status is distinguished from denial and other errors.
The process is terminated on timeout. Synthetic native create/update/read/delete
operations were verified without prompts; no live credentials were changed.

Beginning a new login still clears the saved official item and file only after
the outer store saves outgoing credentials and writes its recovery marker.
Existing values are updated with `add-generic-password -U`. Private saved account
copies remain in the app's separate Keychain service. macOS can still request
authorization after app rebuilds, Keychain locking, or access-policy changes;
this change does not promise that every system prompt disappears forever.
The adapter never grants access to all applications.

The Keychain and file cannot be updated in one atomic transaction. Both are
compared before mutation; a partial failure retains the outer recovery marker
and reports the failure. It never automatically restores an older credential.
Conflicting copies after interruption need explicit inspection/reconciliation
with the official CLI; they are not silently overwritten.

Switching blocks detected `agy`, Antigravity desktop/helper/daemon, and known
macOS language-server processes. Process names and local byte comparisons are
best-effort safeguards, not a global lock respected by Google software.
Credentials can be shared with other official Antigravity clients; no claim is
made that running clients switch their in-memory account.

Only personal Google login is supported initially. Usage is available in 0.2.1 through the official read-only report described below. A real second-account login and A → B → A acceptance test remain
separate from synthetic store tests and native compilation.

## Official usage report (0.2.1)

Installed CLI version: 1.2.7. Its `agy changelog` entry for 1.1.11 introduces read-only print-mode `/usage` and `/quota` reports without an agent turn, quota consumption or conversation creation. `agy --version` is checked before requesting one. Earlier print-mode behavior must not be used.

Live command verified: `agy --disable-slash-commands=false -p /usage --output-format json --print-timeout 20s`. The response reported `SUCCESS`, `num_turns: 0`, `usage.total_tokens: 0` and an empty `conversation_id`. Actual account data is not included here.

`command.data.groups` contains separate `Gemini Models` and `Claude and GPT models` groups. Bucket IDs observed were `gemini-5h`, `gemini-weekly`, `3p-5h`, and `3p-weekly`; `remaining_fraction` is already the remaining fraction, and `reset_time` is RFC3339. The adapter validates these values and preserves both pools. The UI makes the selected group explicit. The report contains no account email, so the store verifies the native identity before/after the helper.
