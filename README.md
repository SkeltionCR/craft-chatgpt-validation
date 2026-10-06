# Craft ChatGPT connection validation

Windows source patches for seven independent open-source editors, beginning with PhotoCraft.
This repository contains source patches and a build recipe. It does not distribute the
upstream projects' branded assets or modified installers.

Upstream repositories and exact base commits are in `projects.json`. The patches add an
optional ChatGPT connection using the official public-client OAuth flow, PKCE, verified
ID tokens, app-specific encrypted storage protected by Windows Credential Manager,
renewal, disconnect, and headless account commands. They do not implement AI editing.

## Build and validation

The manually dispatched **Windows validation** workflow runs on a standard GitHub-hosted
Windows runner, with read-only repository permission. Select `photocraft` first, then
each other project. It checks out the exact upstream commit, verifies and applies its
patch, formats source, updates the dependency lockfile while retaining upstream pins,
runs the app's ChatGPT tests,
exercises the connection controls, renders the actual connection panel offscreen,
checks Clippy, and runs the upstream `cargo xtask ci` gate.

The job log includes a SHA-256-verified, base64-encoded final source patch between
`CRAFT_PATCH_START` and `CRAFT_PATCH_END`, allowing the local checkout to receive
formatting and lockfile changes even when validation reports a failure. No binary,
cache, or artifact storage is requested by this workflow.
The panel preview uses a synthetic disconnected account and a test editor surface;
it never opens a browser or reads a person's stored credentials. Its PNG is returned
in the job log between `CRAFT_IMAGE_START` and `CRAFT_IMAGE_END` with a checksum.

Status is authoritative only in the workflow results. Source parsing is not compilation,
and a passing test suite does not imply that an actual ChatGPT account has been connected.
Review a live sign-in and the editor's account panel before using account credentials.

Source contract: https://developers.openai.com/siwc/token-sharing-open-source/sign-in

The underlying upstream source is licensed MIT OR Apache-2.0. Original notices remain in
each checked-out upstream project. These patches contain no Adobe assets. Trademark
assets from upstream remain in its ephemeral build checkout and are not redistributed.
