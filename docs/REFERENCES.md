# References checked during implementation

Checked 2026-09-19. Documentation and client behavior can evolve; validate against the installed official Codex version when updating this adapter.

## Official behavior

- OpenAI, Codex authentication: https://developers.openai.com/codex/auth — file/keyring/auto credential storage, CODEX_HOME, and credential sensitivity. This address currently redirects to the official ChatGPT Learn documentation.
- OpenAI, Codex App Server: https://developers.openai.com/codex/app-server — initialization, ChatGPT login, current-account reads, usage windows, reset timestamps, multi-bucket responses. Only the documented account/login/usage subset is used.
- OpenAI Codex source: https://github.com/openai/codex — the official installed client remains responsible for OAuth and any token refresh. No fork is bundled.

## UI / implementation-direction inspiration, not copied code

- CodexBar: https://github.com/steipete/CodexBar — compact native menu quota presentation, progress bars, reset countdowns and timestamped states. The README screenshot and the Codex provider notes informed the UI and choice of official CLI RPC: https://github.com/steipete/CodexBar/blob/main/docs/codex.md .
- Lampese Codex Switcher: https://github.com/Lampese/codex-switcher — discoverable account list and tray switching, together with attention to refreshed credentials and running clients.

All application source and artwork in this repository were independently authored. No source, font files, screenshot, logo, or binary from the above community projects is included. The preview is our own HTML rendering with synthetic data, not a screen capture of any of those projects.

## CI and platform

- Official GitHub checkout action: https://github.com/actions/checkout .
- Official GitHub artifact action: https://github.com/actions/upload-artifact .
- Swift Package Manager: https://www.swift.org/documentation/package-manager/ .
- Apple MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra .
- Apple Security framework: https://developer.apple.com/documentation/security .

The CI uses supported major action references to keep maintenance small; a stricter deployment should pin audited immutable commit SHAs and update them deliberately. No GitHub write token is needed for the supplied test/build workflow.

- Apple DTS, Keychain implementation / entitlement distinction: https://developer.apple.com/forums/thread/114456 . The self-built app deliberately uses the ordinary Mac login Keychain rather than claiming a provisioned Data Protection access group.
- GitHub CLI authentication and repository creation: https://cli.github.com/manual/gh_auth_login and https://cli.github.com/manual/gh_repo_create .
