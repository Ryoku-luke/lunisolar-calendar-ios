# ios-dev-helper

A DeepSeek Harness **Host plugin** that gives the Agent three iOS development
capabilities, plus project-appropriate SwiftUI guidance.

| Capability | Tools |
|---|---|
| Xcode build | `xcode_build`, `xcode_info` |
| Simulator control | `simulator_control`, `simulator_install_launch` |
| SwiftUI / HIG guidance | the `ios-dev-helper/swiftui` system-prompt section (not a tool) |

Every external process goes through the harness `subprocess` Service
(`ctx.subprocess`), so children inherit the harness's own authority, are subject
to its SIGTERM→SIGKILL grace ladder, and are joined at composition teardown.
The plugin imports **no** packages and uses no `node:child_process`, so it can
never fail on module resolution.

## Layout

| Path | Role |
|---|---|
| `src/index.ts` | Plugin source — the file to edit. |
| `lib/index.js` | Built entry point. **This is what DSH loads.** |
| `lib/types/index.d.ts` | Generated declarations. |
| `tsconfig.json` | Build configuration. |
| `package.json` | Manifest; `dsh.bundle.patch` marks this package as a bundle. |
| `cordis.patch.yml` | Bundle patch that inserts the plugin row. |

## Why there is a build step

Node refuses to strip TypeScript types for any module whose real path is under a
`node_modules` directory (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`), and
`install_bundle` links this package into the profile's `node_modules`. A `.ts`
entry point therefore cannot activate as an installed plugin. `package.json`
points at the built `lib/index.js` for that reason — `src/index.ts` stays the
authored source.

Rebuild after editing `src/`:

```sh
npm run build      # or: npx tsc -p tsconfig.json
```

## Tools

### `xcode_build`

Runs `xcodebuild` and parses its diagnostics into bullets: `error`/`warning`
lines that carry a position become `file:line:col: severity: message`, and
`xcodebuild`-level failures with no position (a missing scheme, an unmatched
destination) become `<producer>: severity: message`.

- Auto-discovers the `.xcworkspace`/`.xcodeproj` and the scheme in the working
  directory. With several schemes it picks the one named after the project or
  workspace (Xcode's own convention for the app target) and says so in the
  notes; pass `scheme` to build a different one.
- `action`: `build` (default), `test`, `clean`, `build-for-testing`,
  `test-without-building`.
- Composes a `-destination` from `simulator` + `os` when `destination` is
  omitted, e.g. `simulator: "iPhone 17 Pro"`, `os: "26.5"`.
- Marks the build not-ok when `warningCount > 0` **and** `treatWarningsAsErrors`
  is on, mirroring this repository's `Tools/run_tests.sh` rule that compiler
  warnings are failures.
- Runs with `isConcurrencySafe: () => false`: parallel `xcodebuild` runs
  interfere through the shared simulator and DerivedData.

### `xcode_info`

Reports the discovered target, its schemes, and the available simulator
runtimes. Call it before a first `xcode_build` when the scheme is unknown.

### `simulator_control`

`action`: `list`, `boot`, `shutdown`, `booted`, `open`, `erase`, `delete`,
`runtime_list`. `device` accepts a name, a UDID, or `booted`. `erase` and
`delete` require `confirm: true`; `boot` on an already-booted device is treated
as success rather than an error.

### `simulator_install_launch`

Installs a built `.app` on a simulator and optionally launches it.
`bundle_id` is required to launch and optional when only installing.

## Configuration

Values come from the `config:` block in `cordis.patch.yml` and are validated by
the plugin at activation (there is no `Config` export, so no schemastery
dependency). An unknown key is ignored; an absent key keeps its default.

| Key | Default | Meaning |
|---|---|---|
| `workspaceRoot` | `''` (use the Agent's cwd) | Pin builds to one checkout. |
| `xcodebuildPath` | `xcodebuild` | Absolute path or PATH name. |
| `xcrunPath` | `xcrun` | Absolute path or PATH name. |
| `buildTimeoutMs` | `900000` | Budget for one `xcodebuild`. |
| `simctlTimeoutMs` | `120000` | Budget for one `simctl` call. |
| `maxOutputBytes` | `8388608` | Per-stream collector budget. |
| `maxDiagnostics` | `40` | Diagnostic bullets surfaced to the model. |
| `maxOutputChars` | `6000` | Raw output tail surfaced to the model. |
| `graceMs` | `3000` | SIGTERM→SIGKILL grace. |
| `injectSwiftUIGuidance` | `true` | Register the prompt section. |
| `treatWarningsAsErrors` | `true` | Warning-only build counts as failed. |

## Install

```sh
# from the profile, or with plugin_manager action: install_bundle
dsh plugin --profile "$DSH_PROFILE" install /path/to/Tools/ios-dev-helper
```

## Notes and limits

- **Sandbox**: these tools spawn processes with the harness process's own
  authority. They are not confined by the DSH *file* sandbox that governs the
  `bash` tool, so `xcodebuild` can reach `~/Library/Caches` and DerivedData. The
  subprocess service does scrub credential-shaped environment names
  (`*KEY*`, `*PASSWORD*`, `*SECRET*`, `*TOKEN*`) and all `DSH_*` names from the
  child environment.
- **Diagnostics, not raw logs**: the diagnostic bullets carry only `error` and
  `warning`; `note` lines (input encodings, dependency-order chatter) are dropped
  so a clean build does not look alarming. The raw log is bounded to the **last**
  `maxOutputChars` characters, because a build log puts its verdict at the end;
  raise that key when you need more of it.
- `simulator_control` deliberately exposes no `spawn` action; arbitrary process
  execution stays with `bash`.
