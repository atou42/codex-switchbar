# Inactive-account usage research (2026-09-26)

## Shipped

Account rows display the persisted 7-day observation and reset timestamp without switching. Cache age is explicit; a passed reset never implies a new 100% balance. No background account rotation or cross-device synchronization was added.

## Codex candidate, not enabled

The official account/rateLimits/read request has no target-account selector. The experimental chatgptAuthTokens login can establish an independent helper identity using an access token only. Current official source describes memory-only external tokens but also marks the interface unstable/internal; compatibility must be handled explicitly.

A local synthetic probe using Codex 0.155.0 accepted experimental initialization and external-token login. It ran in a disposable worker directory with cli_auth_credentials_store="ephemeral". A sentinel auth.json remained byte-for-byte unchanged, and a recursive scan found no saved copy of the synthetic access token. No real credentials, Keychain items, or quota requests were used. This proves local protocol acceptance and file isolation, not live quota success.

Any implementation should use a short-lived isolated helper, never supply refresh tokens, never swap shared authentication, validate the selected saved identity before updating its cache, preserve old observations on failure, and report expired authorization clearly. Temporary worker metadata needs cleanup. This is not a permanent per-account Codex workspace. Availability must be tested against the installed CLI rather than assumed from a version string alone.

Valid server queries can observe usage incurred on other devices; locally cached observations cannot. Copied refresh-token lineages are unsafe to rotate independently across devices, so this design deliberately does not refresh them.

## Antigravity limitation

Inspected official CLI help and documentation do not expose a target-account or external-token override for /usage. Changing HOME alone does not isolate the shared macOS Keychain item. Do not silently swap the live item to make a refresh button appear to work.

## Sources

- [Official app-server guide](https://learn.chatgpt.com/docs/app-server)
- [Official external-token auth implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/manager.rs)
- [Official protocol definitions](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/common.rs)
- [Antigravity CLI reference](https://antigravity.google/docs/cli/reference/)
