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

Existing Keychain items use `SecItemUpdate` to retain their access controls.
Beginning a new login clears the saved official item and file only after the
outer store has saved the outgoing credentials and written its recovery marker.
Re-created items follow normal macOS access policy and may prompt the official
CLI on first use. The adapter does not grant access to all applications.

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

Only personal Google login is supported initially. Usage is unavailable through
this adapter. A real second-account login and A → B → A acceptance test remain
separate from synthetic store tests and native compilation.
