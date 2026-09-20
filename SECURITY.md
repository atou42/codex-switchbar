# Security boundary

This is a personal local credential utility, not a security-reviewed credential service or an OpenAI-endorsed account manager. Source delivery is not evidence of a completed Mac audit. Read `docs/VALIDATION.md` before using an important account.

## What is protected

Saved OAuth blobs go into macOS Keychain generic-password items, keyed by random UUID, without Keychain synchronization. For a self-built ad-hoc-signed app, this adapter explicitly uses the ordinary macOS login Keychain, not provisioned Data Protection access groups. It does not promise hardware-backed or `ThisDeviceOnly` enforcement; Keychain backups and access prompts follow macOS policy. The shared official `auth.json` is necessarily still a sensitive file. Application directories are 0700 and writes are 0600, use no-follow opens, reject non-regular files/multiple hardlinks/foreign owners, and atomically replace files. Symlinked homes are deliberately unsupported.

The account index and transaction journal contain no access, refresh, or ID token. They still contain private metadata (email, account/workspace identity, local names, usage), so they are private files, not public assets. Raw credentials are never logged, copied to the clipboard, sent in command-line arguments, or embedded in the public project. The app performs minimal JWT-payload decoding solely for LOCAL identity routing, not authentication or signature verification; the official service remains the authority.

Switches first save the latest live credentials, validate the target identity, and record a recovery marker. Process and file checks run again before replacement. A failed Keychain save does not proceed to overwrite the live credential. Recovering an interrupted operation never automatically replays an old credential. A missing live login is not silently resurrected.

The source publication script requires a fresh Git directory and a specific authenticated owner, scans common secret patterns, and refuses to modify existing remotes. This is a lightweight precaution, not a comprehensive secret scanner or proof of absence of all sensitive data.

## What is deliberately NOT promised

- **No seamless identity change in already-running clients.** The menu labels the file login. Explicit switches wait for detected Codex clients to exit. There is no force-switch/kill button. Queued requests expire after five minutes.
- **No global lock on the official client.** This app's file lock is advisory and other programs need not honor it. Byte comparison and atomic rename are not a cross-process compare-and-swap transaction. Someone can launch or rename a client in the remaining race window; custom wrappers, remote backends, other OS users, and future process names can escape detection. Stop other account managers and close relevant clients before switching. Do not claim this is mathematically race-free.
- **No guarantee of permanent OAuth validity or immunity from account restrictions.** Server revocation, policy, expiry, passwords, and another machine consuming the same refresh-token lineage can invalidate credentials. Let the official login flow recover; do not distribute saved tokens or pool them across machines.
- **No protection against malicious software running as you.** Your official CLI must be trusted; it receives the same sensitive home path. The app cannot protect plaintext active auth, process memory, or Keychain decisions from a compromised login session. Keychain prompts may recur after ad-hoc rebuilds. Do not grant blanket access to all apps.
- **No organization/persona data isolation.** Shared sessions, history, skills, and MCP configuration remain shared. A personal account may access locally stored work context. Comply with employer workspace and data-handling rules.
- **No comprehensive TOML support.** To avoid rewriting user config, a conservative top-level recognizer is used. Ambiguous, quoted, duplicate, or multiline layouts are rejected for manual inspection, including some otherwise-valid TOML. No automatic migration of OS-stored official credentials occurs.

## Network boundary

Codex Switch itself has no custom HTTP client, network listener, proxy, or telemetry. It communicates through pipes with your installed official `codex app-server`. That child can access OpenAI for login and usage, may perform its normal official token refresh, and can start the official OAuth loopback callback. Shared Codex configuration may also affect what its startup does. This is not an offline-only application and not a guarantee that the official process never initializes any other configured subsystem.

Only authentication/account/usage RPCs are sent. No thread/turn/tool requests, generated model work, external-token injection, quota-reset redemption, browser-cookie reads, custom refresh endpoints, or arbitrary proxy URLs. Server-initiated RPC requests are rejected. OAuth browser URLs are restricted to an explicit HTTPS official-host allowlist with no username/password/port. Responses are size-limited and timeouts/cancellation terminate only the helper this app launched, never an existing user Codex process.

Usage is queried only for the currently saved live account and only through official Codex. Inactive accounts show dated cache; no token-refresh worker is maintained for them. A failed lookup leaves the cache but does not silently replace it with zeros. No background account rotation is used to bypass quotas.

## Recovery and reporting

Use Settings → Reconcile & recover for an interrupted operation. If identity cannot be established, inspect the real official login rather than restoring random backups. Clearing the operation marker does not restore or delete credentials. Forgetting a saved account is not logout.

Do not post `auth.json`, Keychain exports, OAuth callback URLs, full JWTs, account indexes, or terminal logs containing credentials to public issues. For a bug report, use a synthetic fixture and share only a minimal redacted reproduction, platform/tool versions, and sanitized error text. If a credential has leaked, revoke it through the provider's current security controls rather than relying on this application to secure an already exposed token.

## Local terminal control

The CLI connects to an owner-only Unix-domain socket in the private application-support directory. Both peers verify the macOS user ID. Messages are limited to 1 MiB and transport waits are bounded. Requests contain actions and account labels/IDs, never credentials. Operations execute in the existing GUI model, preserving busy/queued states and process checks. Existing socket paths are rejected, not replaced; normal termination removes only the socket this app created. This does not protect against malicious software already running as the same user.

Device-code login uses the official `chatgptDeviceCode` RPC. Its short-lived user code and allowlisted verification URL are returned only to the current user's local CLI while login is pending and shown in the app. They are not persisted, logged, or included in the account registry. Long-lived credentials are never returned over local control.

## Antigravity CLI adapter (0.2.0 experimental)

Antigravity uses a separate registry and saved-secret Keychain service. The adapter handles only the inspected consumer OAuth schema and preserves unknown credential fields as opaque bytes. No custom OAuth exchange, refresh request, model turn, cookie read, or API token injection is used. Official `agy` performs authentication in Terminal. Before starting a new login the outgoing credential is saved, a journal is written, and the live login is removed so the official sign-in flow can run. Cancellation does not replay an old login; an explicitly selected saved account can be restored later.

The adapter reads the official primary Keychain entry and its file copy, rejecting different identities and unsupported storage modes. Keychain and file writes are not atomic as a pair. A partial failure leaves the journal and reports an error; recovery follows the actual current state and does not silently undo writes. An inconsistent pair requires manual inspection. Process detection is best effort and includes Antigravity clients, not just the CLI. Already running clients are never killed, and switching is refused while detected clients remain.

Account identity is locally decoded from Google's stored ID token for routing, not treated as cryptographic login verification. A local switch/read-back is not proof that Google's server accepts a saved login. Real A → B → A validation requires signing into two accounts through the official client. Desktop Antigravity shares some authentication state; only CLI behavior is targeted. No quota collection is implemented for Antigravity.
