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
FilmCraft and EffectCraft checks use the release profile required by their upstream
gate. The job permits up to 360 minutes for a cold build. Both check their engine
tests early, then still run every full workspace gate. PrintCraft also installs
the pinned dependency checker and runs its unchanged license/advisory policy first.
The `compiler_jobs` choice limits concurrent compiler processes to 4, 2, or 1.
It preserves the release profile and all CI gates. Different choices have independent
concurrency groups, allowing a resource trial to run alongside an existing build.

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

## Validation results

| Project | Full Windows CI | Live account |
|---|---|---|
| PhotoCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37526632188) | Not exercised |
| VectorCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37526641875) | Not exercised |
| FilmCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37858950216) | Not exercised |
| LightCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37592193475) | Not exercised |
| PrintCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37536527821) | Not exercised |
| EffectCraft | [Pending](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/38091148903) | Not exercised |
| DesignCraft | [Passed](https://github.com/SkeltionCR/craft-chatgpt-validation/actions/runs/37526643074) | Not exercised |

Panel previews use synthetic disconnected accounts and a test editor surface.
A CI result proves only the checks performed by that run; actual browser authorization
and account renewal with a person's ChatGPT account remain untested.

Full validation is still pending for effectcraft.

Run 38073568886 passed all 174 GPU and 177 renderer tests, plus all eight
named authentication tests, formatting and strict workspace Clippy.
Full workspace testing reported exactly one failed target: effectcraft-text
(42 passed, one failed). Its variable-font fixture assumed the first installed
weight axis changes advances; valid weight axes may preserve advances.
The revised test uses an original bundled variable font: width changes both
advances and outlines; weight changes outlines while preserving advances.
Original width/outline difference assertions remain, with expected widths
and constant-advance weight coverage added. Production text code is unchanged.
An independent font-data oracle checked geometry, metrics and reproducibility.
Replacement full-validation run: 38091148903. Status: pending.
Observed live in the replacement: all 43 text unit tests passed, with zero
failures, ignores or filters. The bundled fixture completed its width/weight
assertions, the system-font menu integration test passed, and strict text
Clippy passed.
The replacement also passed all 177 renderer tests, with zero failures
and one existing ignore, confirmed by its live suite summary and marker.
All 174 GPU tests passed in the replacement, with zero failures, ignores
or filters, confirmed by its live suite summary and marker.
Full workspace CI, explicit authentication and connection-panel results
still await terminal verification. Early suites do not establish full success.
