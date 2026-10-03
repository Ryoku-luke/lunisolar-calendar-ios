/**
 * ios-dev-helper — an iOS development companion plugin for DeepSeek Harness.
 *
 * It contributes three capabilities to whatever Agent scope loads it:
 *
 * 1. Xcode build (`xcode_build`, `xcode_info`) — wraps `xcodebuild`, discovers the
 *    workspace/project and scheme from the Agent's working directory, and parses
 *    compiler diagnostics out of the build output into model-friendly bullets.
 * 2. Simulator control (`simulator_control`, `simulator_install_launch`) — wraps
 *    `xcrun simctl` to boot/shutdown/list simulators and to install + launch a
 *    built `.app` bundle.
 * 3. SwiftUI guidance — a system-prompt section asking the Agent to prefer SwiftUI
 *    and to follow Apple's current Human Interface Guidelines.
 *
 * Every external process goes through the `subprocess` Service (`ctx.subprocess`),
 * so spawned children inherit the harness's own authority and are tracked for
 * teardown by the composition. No `node:child_process` import is used.
 *
 * @module ios-dev-helper
 */
/** Services this plugin needs. The plugin stays inactive without them. */
export const inject = ['tools', 'subprocess', 'systemPrompt'];
const DEFAULT_CONFIG = {
    workspaceRoot: '',
    xcodebuildPath: 'xcodebuild',
    xcrunPath: 'xcrun',
    buildTimeoutMs: 15 * 60 * 1000,
    simctlTimeoutMs: 2 * 60 * 1000,
    maxOutputBytes: 8 * 1024 * 1024,
    maxDiagnostics: 40,
    maxOutputChars: 6000,
    graceMs: 3000,
    injectSwiftUIGuidance: true,
    treatWarningsAsErrors: true,
};
/** Payload of the SwiftUI/HIG system-prompt section owned by this plugin. */
const SWIFTUI_GUIDANCE = `## iOS development conventions (ios-dev-helper)

When you write or modify UI code for an Apple platform in this session:

- **Prefer SwiftUI.** Reach for a UIKit/AppKit view only when the requested control or
  behavior has no SwiftUI equivalent, and say why in one line when you do.
- **Follow Apple's current Human Interface Guidelines**: use the platform's standard
  controls and navigation patterns (NavigationStack, TabView, sheets, menus) instead of
  hand-rolled substitutes; support Dynamic Type with semantic fonts
  (\`.font(.headline)\`, never a hard-coded point size for body text); respect safe areas,
  layout margins, and the user's light/dark appearance and accent color.
- **Accessibility is part of "done".** Give every meaningful control a label, keep
  hit targets at least 44x44 pt, and provide text alternatives for icon-only affordances.
- **State belongs in observable models.** Use \`@Observable\` (or \`ObservableObject\` on
  older deployment targets), \`@State\`, and \`@Bindable\` per their intended ownership
  rules; keep views declarative and free of side effects in \`body\`.
- **Prefer modern async APIs** (\`Task\`, \`.task {}\`, \`async/await\`) over completion
  handlers and manual dispatch queues.
- Locate UI strings in the project's existing localization mechanism instead of
  inlining new literals when the project already localizes.

After changing Swift sources, build with the \`xcode_build\` tool rather than guessing,
and report the compiler diagnostics it returns.`;
/** Clamp a number into an inclusive range. */
function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value));
}
/** Read a positive finite number from raw config, else the fallback. */
function positiveNumber(raw, fallback, low, high) {
    const value = typeof raw === 'number' ? raw : Number.NaN;
    return Number.isFinite(value) && value > 0 ? clamp(value, low, high) : fallback;
}
/** Resolve raw plugin config (from `cordis.patch.yml`) into a complete config. */
function resolveConfig(raw) {
    const source = raw !== null && typeof raw === 'object' ? raw : {};
    const text = (key, fallback) => {
        const value = source[key];
        return typeof value === 'string' && value.trim().length > 0 ? value.trim() : fallback;
    };
    const flag = (key, fallback) => {
        const value = source[key];
        return typeof value === 'boolean' ? value : fallback;
    };
    return {
        workspaceRoot: text('workspaceRoot', DEFAULT_CONFIG.workspaceRoot),
        xcodebuildPath: text('xcodebuildPath', DEFAULT_CONFIG.xcodebuildPath),
        xcrunPath: text('xcrunPath', DEFAULT_CONFIG.xcrunPath),
        buildTimeoutMs: positiveNumber(source.buildTimeoutMs, DEFAULT_CONFIG.buildTimeoutMs, 1000, 6 * 60 * 60 * 1000),
        simctlTimeoutMs: positiveNumber(source.simctlTimeoutMs, DEFAULT_CONFIG.simctlTimeoutMs, 1000, 60 * 60 * 1000),
        maxOutputBytes: positiveNumber(source.maxOutputBytes, DEFAULT_CONFIG.maxOutputBytes, 64 * 1024, 128 * 1024 * 1024),
        maxDiagnostics: positiveNumber(source.maxDiagnostics, DEFAULT_CONFIG.maxDiagnostics, 1, 500),
        maxOutputChars: positiveNumber(source.maxOutputChars, DEFAULT_CONFIG.maxOutputChars, 500, 200000),
        graceMs: positiveNumber(source.graceMs, DEFAULT_CONFIG.graceMs, 100, 30000),
        injectSwiftUIGuidance: flag('injectSwiftUIGuidance', DEFAULT_CONFIG.injectSwiftUIGuidance),
        treatWarningsAsErrors: flag('treatWarningsAsErrors', DEFAULT_CONFIG.treatWarningsAsErrors),
    };
}
/** True when `value` is a non-empty string. */
function isNonEmptyString(value) {
    return typeof value === 'string' && value.trim().length > 0;
}
/** Trim trailing whitespace and cap a string at `max` characters, keeping the head. */
function bounded(text, max) {
    const trimmed = text.trim();
    return trimmed.length <= max
        ? { text: trimmed, truncated: false }
        : { text: `${trimmed.slice(0, max)}\n… (${trimmed.length - max} more characters truncated)`, truncated: true };
}
/**
 * Keep the *end* of a string, capped at `max` characters.
 *
 * Build logs put their verdict last (`** BUILD SUCCEEDED **`, the error count,
 * the failing target), so the tail is the useful half of a long log.
 */
function boundedTail(text, max) {
    const trimmed = text.trim();
    return trimmed.length <= max
        ? { text: trimmed, truncated: false }
        : { text: `… (${trimmed.length - max} earlier characters truncated)\n${trimmed.slice(trimmed.length - max)}`, truncated: true };
}
/**
 * Run one managed child process to completion and collect its bounded output.
 * A nonzero exit code is a normal result; only infrastructure failures throw.
 */
async function runCommand(ctx, config, options) {
    const subprocess = ctx.subprocess ?? ctx.get('subprocess');
    if (subprocess === undefined) {
        return {
            output: 'the `subprocess` service is not available in this scope, so no command was executed',
            exitCode: null,
            signal: null,
            lossy: false,
            timedOut: false,
            unavailable: true,
        };
    }
    // A child that outlives its budget is signalled, then killed after `graceMs`.
    const controller = new AbortController();
    const caller = options.signal;
    const onCallerAbort = () => controller.abort();
    if (caller !== undefined) {
        if (caller.aborted)
            controller.abort();
        else
            caller.addEventListener('abort', onCallerAbort, { once: true });
    }
    let timedOut = false;
    const collect = { maxBytes: config.maxOutputBytes };
    const handle = subprocess.spawn({
        argv: options.argv,
        cwd: options.cwd,
        stdio: { stdin: 'ignore', stdout: collect, stderr: collect },
        graceMs: config.graceMs,
        signal: controller.signal,
    });
    const timer = setTimeout(() => {
        timedOut = true;
        controller.abort();
    }, options.timeoutMs);
    try {
        const outcome = await handle.done;
        if (timedOut && outcome.exitCode === null)
            handle.terminate();
        const stdout = handle.collected.stdout?.readFrom(0);
        const stderr = handle.collected.stderr?.readFrom(0);
        const pieces = [];
        if (stdout !== undefined && stdout.text.length > 0)
            pieces.push(stdout.text);
        if (stderr !== undefined && stderr.text.length > 0) {
            pieces.push(pieces.length > 0 && !stdout.text.endsWith('\n') ? `\n[stderr]\n${stderr.text}` : `[stderr]\n${stderr.text}`);
        }
        return {
            output: pieces.join(''),
            exitCode: outcome.exitCode,
            signal: outcome.signal,
            lossy: stdout?.lossy === true || stderr?.lossy === true,
            timedOut,
            unavailable: false,
        };
    }
    catch (error) {
        const detail = error instanceof Error ? error.message : String(error);
        return {
            output: `failed to run \`${options.argv.join(' ')}\`: ${detail}`,
            exitCode: null,
            signal: null,
            lossy: false,
            timedOut: false,
            unavailable: true,
        };
    }
    finally {
        clearTimeout(timer);
        caller?.removeEventListener('abort', onCallerAbort);
    }
}
// Xcode diagnostics look like:
//   /abs/path/File.swift:12:5: error: cannot find 'foo' in scope
//   /abs/path/File.swift:12: error: ...
//   <unknown>:0: error: ...            (no usable path)
const DIAGNOSTIC_PATTERN = /^(.*?):(\d+)(?::(\d+))?:\s*(error|warning|note):\s*(.*)$/;
// `xcodebuild` also reports failures that carry no file/line at all, and those
// are exactly the ones a caller most needs (a missing scheme, an unmatched
// destination). Without these fallbacks a failed build reported "0 errors".
//   xcodebuild: error: The project named "X" does not contain a scheme named "Y"
//   error: something went wrong
const TOOL_DIAGNOSTIC_PATTERN = /^([^\s:][^:]*?):\s*(error|warning):\s*(.*)$/;
const BARE_DIAGNOSTIC_PATTERN = /^(error|warning):\s*(.*)$/;
const TARGET_HEADER_PATTERN = /^===\s*(.+?)\s*===$/;
/**
 * Parse compiler diagnostics from `xcodebuild` output.
 *
 * Only `error` and `warning` become bullets: `note` lines are informational
 * (input encodings, dependency-order chatter) and on a clean build they used to
 * bury the verdict under a dozen irrelevant lines.
 */
function parseDiagnostics(output, limit) {
    const found = [];
    for (const line of output.split(/\r?\n/)) {
        if (TARGET_HEADER_PATTERN.test(line))
            continue;
        let file = '';
        let lineNumber;
        let column;
        let severity = '';
        let message = '';
        const located = DIAGNOSTIC_PATTERN.exec(line);
        if (located !== null) {
            const [, locatedFile, locatedLine, locatedColumn, locatedSeverity, locatedMessage] = located;
            file = locatedFile.trim();
            lineNumber = Number(locatedLine);
            column = locatedColumn !== undefined ? Number(locatedColumn) : undefined;
            severity = locatedSeverity;
            message = locatedMessage;
        }
        else {
            const bare = BARE_DIAGNOSTIC_PATTERN.exec(line);
            const tool = bare === null ? TOOL_DIAGNOSTIC_PATTERN.exec(line) : null;
            const match = bare ?? tool;
            if (match === null)
                continue;
            // For `xcodebuild: error: ...` the leading token names the producer.
            file = bare !== null ? 'xcodebuild' : (match[1] ?? 'xcodebuild').trim();
            severity = match[bare !== null ? 1 : 2] ?? '';
            message = match[bare !== null ? 2 : 3] ?? '';
        }
        if (severity === 'note')
            continue;
        // Skip the SwiftPM/sandbox cache noise this project deliberately whitelists.
        if (/swiftpm|not writable|readonly database/i.test(message))
            continue;
        found.push({
            file: file.length === 0 ? 'xcodebuild' : file,
            ...(lineNumber !== undefined ? { line: lineNumber } : {}),
            ...(column !== undefined ? { column } : {}),
            severity,
            message: message.trim(),
        });
        if (found.length >= limit)
            break;
    }
    return found;
}
/** Render diagnostics as compact single lines, deduplicated in order. */
function formatDiagnostics(diagnostics) {
    const seen = new Set();
    const lines = [];
    for (const item of diagnostics) {
        // A tool-level diagnostic has no position; print just the producer name
        // rather than a misleading `:0`.
        const where = item.line !== undefined
            ? `${item.file}:${item.line}${item.column !== undefined ? `:${item.column}` : ''}`
            : item.file;
        const line = `- ${where}: ${item.severity}: ${item.message}`;
        if (seen.has(line))
            continue;
        seen.add(line);
        lines.push(line);
    }
    return lines.join('\n');
}
/** Discover the workspace/project, schemes, and default scheme in one directory. */
async function discoverProject(ctx, config, cwd) {
    const ls = await runCommand(ctx, config, {
        argv: [config.xcrunPath, 'simctl', 'list', 'devices', 'available'],
        cwd,
        timeoutMs: config.simctlTimeoutMs,
    });
    if (ls.unavailable)
        return { schemes: [], diagnostics: '', detectionLog: ls.output };
    const probe = await runCommand(ctx, config, {
        argv: ['/bin/sh', '-c', 'ls -1d *.xcworkspace *.xcodeproj 2>/dev/null'],
        cwd,
        timeoutMs: 15000,
    });
    if (probe.unavailable)
        return { schemes: [], diagnostics: '', detectionLog: probe.output };
    const candidates = probe.output
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.endsWith('.xcworkspace') || line.endsWith('.xcodeproj'));
    if (candidates.length === 0) {
        return { schemes: [], diagnostics: '', detectionLog: `no .xcworkspace or .xcodeproj found in ${cwd}` };
    }
    // A workspace hides the project inside it, so prefer it when both exist.
    const target = candidates.find((name) => name.endsWith('.xcworkspace')) ?? candidates[0];
    const flag = target.endsWith('.xcworkspace') ? '-workspace' : '-project';
    const listed = await runCommand(ctx, config, {
        argv: [config.xcodebuildPath, '-list', flag, target, '-json'],
        cwd,
        timeoutMs: 120000,
    });
    let schemes = [];
    let diagnostics = '';
    const record = parseJsonObject(listed.output);
    if (record !== undefined) {
        const fromJson = record.schemes;
        if (Array.isArray(fromJson))
            schemes = fromJson.filter(isNonEmptyString);
        const project = record.project;
        if (schemes.length === 0 && project !== undefined && Array.isArray(project.schemes)) {
            schemes = project.schemes.filter(isNonEmptyString);
        }
        diagnostics = isNonEmptyString(record.error) ? record.error : '';
    }
    if (schemes.length === 0) {
        // `-json` is unavailable on old toolchains, and a project can legitimately
        // report no schemes: fall back to the human-readable list output.
        schemes = schemesFromText(listed.output);
        if (schemes.length === 0 && listed.exitCode !== 0)
            diagnostics = listed.output;
    }
    return { target, schemes, diagnostics, detectionLog: '' };
}
/**
 * Pull the first top-level JSON object out of mixed tool output.
 *
 * `xcodebuild -list -json` prints its own invocation first, which contains a
 * literal `{` inside the `-destination` value, so a naive `indexOf('{')` finds
 * that brace instead of the document. A real JSON object opens with `"` (a
 * quoted key) or `}` (empty), so each `{` is checked against that before
 * scanning its balanced extent.
 */
function extractJsonObject(output) {
    for (let start = output.indexOf('{'); start >= 0; start = output.indexOf('{', start + 1)) {
        let lookahead = start + 1;
        while (lookahead < output.length && /\s/.test(output[lookahead]))
            lookahead += 1;
        const next = output[lookahead];
        if (next !== '"' && next !== '}')
            continue;
        const candidate = scanBalancedObject(output, start);
        if (candidate !== undefined)
            return candidate;
    }
    return undefined;
}
/** Scan a balanced brace region starting at `start`, honouring string literals. */
function scanBalancedObject(output, start) {
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let index = start; index < output.length; index += 1) {
        const character = output[index];
        if (inString) {
            if (escaped)
                escaped = false;
            else if (character === '\\')
                escaped = true;
            else if (character === '"')
                inString = false;
            continue;
        }
        if (character === '"')
            inString = true;
        else if (character === '{')
            depth += 1;
        else if (character === '}') {
            depth -= 1;
            if (depth === 0)
                return output.slice(start, index + 1);
        }
    }
    return undefined;
}
/**
 * Parse a JSON document out of tool output, tolerating extractor or toolchain
 * surprises. A malformed document yields `undefined` so the caller can fall
 * back to a text form instead of failing the whole tool call.
 */
function parseJsonObject(output) {
    const candidate = extractJsonObject(output);
    if (candidate === undefined)
        return undefined;
    try {
        const parsed = JSON.parse(candidate);
        return parsed !== null && typeof parsed === 'object' ? parsed : undefined;
    }
    catch {
        return undefined;
    }
}
/** Extract the scheme list from the human-readable `xcodebuild -list` output. */
function schemesFromText(output) {
    const match = /Schemes:\s*\n([\s\S]*?)(?:\n\s*\n|$)/.exec(output);
    if (match === null)
        return [];
    return match[1]
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0 && !line.endsWith(':'));
}
/**
 * Choose the scheme that belongs to the inspected target.
 *
 * Xcode's own convention is that an app target carries a scheme named after the
 * project (or workspace), so an exact name match is the safest automatic choice.
 * A scheme merely *starting* with that name (e.g. `App` vs `AppWidgets`) is the
 * next-best guess; anything else is ambiguous and left to the caller.
 */
function preferredScheme(schemes, target) {
    const base = target.replace(/\.(xcodeproj|xcworkspace)$/i, '');
    if (base.length === 0)
        return undefined;
    const lower = base.toLowerCase();
    return (schemes.find((scheme) => scheme === base) ??
        schemes.find((scheme) => scheme.toLowerCase() === lower) ??
        schemes.find((scheme) => scheme.toLowerCase().startsWith(lower)));
}
/** Resolve the working directory for a tool call. */
function resolveCwd(config, requested) {
    if (isNonEmptyString(requested))
        return requested;
    if (config.workspaceRoot.length > 0)
        return config.workspaceRoot;
    return process.cwd();
}
/** Read the runtime-grouped device map from a `simctl ... -j` document. */
function deviceGroups(document) {
    const devices = document.devices;
    return devices !== null && typeof devices === 'object' ? devices : {};
}
/** Render a `simctl list devices -j` document into compact text. */
function formatDevices(document, runtimeFilter) {
    const lines = [];
    for (const [runtime, devices] of Object.entries(deviceGroups(document))) {
        if (runtimeFilter !== undefined && !runtime.toLowerCase().includes(runtimeFilter.toLowerCase()))
            continue;
        lines.push(`## ${runtime.replace('com.apple.CoreSimulator.SimRuntime.', '')}`);
        for (const device of devices) {
            if (device.isAvailable === false)
                continue;
            const name = String(device.name ?? '?');
            const udid = String(device.udid ?? '?');
            const state = String(device.state ?? '?');
            lines.push(`- ${name} [${state}] ${udid}`);
        }
    }
    return lines.length > 0 ? lines.join('\n') : 'no matching simulators';
}
/** Resolve a simulator selector (UDID, `booted`, or a device name) to a UDID. */
async function resolveDevice(ctx, config, cwd, requested) {
    if (!isNonEmptyString(requested)) {
        const booted = await runCommand(ctx, config, {
            argv: [config.xcrunPath, 'simctl', 'list', 'devices', 'booted', '-j'],
            cwd,
            timeoutMs: config.simctlTimeoutMs,
        });
        const document = parseJsonObject(booted.output);
        if (document === undefined)
            return { note: bounded(booted.output, 2000).text };
        const devices = Object.values(deviceGroups(document)).flat();
        const first = devices[0];
        if (first === undefined)
            return { note: 'no booted simulator; boot one with simulator_control first' };
        return { udid: String(first.udid) };
    }
    const selector = requested.trim();
    if (/^[0-9A-Fa-f-]{36}$/.test(selector))
        return { udid: selector };
    if (selector === 'booted')
        return resolveDevice(ctx, config, cwd, undefined);
    const listed = await runCommand(ctx, config, {
        argv: [config.xcrunPath, 'simctl', 'list', 'devices', 'available', '-j'],
        cwd,
        timeoutMs: config.simctlTimeoutMs,
    });
    const document = parseJsonObject(listed.output);
    if (document === undefined)
        return { note: bounded(listed.output, 2000).text };
    const matches = [];
    for (const devices of Object.values(deviceGroups(document))) {
        for (const device of devices) {
            if (device.isAvailable === false)
                continue;
            const name = String(device.name ?? '');
            if (name === selector)
                matches.push(device);
            else if (matches.length === 0 && name.toLowerCase() === selector.toLowerCase())
                matches.push(device);
        }
    }
    // Prefer an already-booted match so repeated calls target the same device.
    const booted = matches.find((device) => String(device.state) === 'Booted') ?? matches[0];
    if (booted === undefined)
        return { note: `no available simulator matches \`${selector}\`` };
    return { udid: String(booted.udid) };
}
/** A `ContentBlock`-shaped text block. */
function textBlock(text) {
    return { type: 'text', text };
}
/** Build the plugin. */
export function apply(ctx, rawConfig) {
    const config = resolveConfig(rawConfig);
    const disposers = [];
    /** Register one tool definition, keeping its disposer for teardown. */
    const register = (definition) => {
        disposers.push(ctx.tools.register(definition));
    };
    // ---------------------------------------------------------------------------
    // Capability 1: Xcode build
    // ---------------------------------------------------------------------------
    register({
        name: 'xcode_build',
        description: 'Build, test, or clean an Xcode workspace/project with `xcodebuild`, then parse the compiler ' +
            'diagnostics out of the output. Omit `target` and `scheme` to auto-discover them from the ' +
            'working directory; a multi-scheme project picks the scheme named after the project. Errors and ' +
            'warnings come back as `file:line:col: severity: message` bullets, and `xcodebuild`-level failures ' +
            'that carry no position (a missing scheme, an unmatched destination) as `<producer>: severity: message`.',
        // Concurrent xcodebuild runs interfere through the shared simulator and
        // DerivedData (this project measured flaky clones), so run exclusively.
        isConcurrencySafe: () => false,
        timeoutMs: config.buildTimeoutMs + 30000,
        // `parameters` is sent to the model provider verbatim, so it must be a real
        // object-rooted JSON Schema — never the author-facing property map. Both
        // OpenAI-style `parameters` and Anthropic-style `input_schema` require
        // `type: "object"` with `properties`/`required`; a bare property map is
        // rejected by the provider with a 400 before the model ever runs.
        parameters: {
            type: 'object',
            properties: {
                action: {
                    type: 'string',
                    enum: ['build', 'test', 'clean', 'build-for-testing', 'test-without-building'],
                    description: 'The xcodebuild action. Defaults to `build`.',
                },
                target: {
                    type: 'string',
                    description: 'Path to a .xcworkspace or .xcodeproj. Auto-discovered in cwd when omitted.',
                },
                scheme: {
                    type: 'string',
                    description: 'Scheme name. The only scheme is used when the target exposes exactly one.',
                },
                configuration: {
                    type: 'string',
                    description: 'Build configuration, e.g. Debug or Release. Defaults to Debug.',
                },
                destination: {
                    type: 'string',
                    description: 'Full -destination value, e.g. `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5`. ' +
                        'When omitted for a simulator action, one is composed from `simulator` and `os`.',
                },
                simulator: {
                    type: 'string',
                    description: 'Simulator device name used to compose a destination, e.g. `iPhone 17 Pro`.',
                },
                os: {
                    type: 'string',
                    description: 'Simulator OS version used to compose a destination, e.g. `26.5`.',
                },
                only_testing: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Test identifiers for -only-testing, e.g. ["LunisolarCalendarUITests"].',
                },
                derived_data_path: {
                    type: 'string',
                    description: 'Value for -derivedDataPath. Defaults to the toolchain default.',
                },
                extra_args: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Additional raw arguments appended to the xcodebuild invocation.',
                },
                cwd: {
                    type: 'string',
                    description: 'Directory to run in. Defaults to the plugin working directory.',
                },
            },
        },
        // `output.schema` is a compiled JSON Schema, not the author DSL: requiredness
        // at the object root is a `required: [...]` array. A nested `required: true`
        // is only legal inside the `properties` map of an object node.
        output: {
            schema: {
                type: 'object',
                additionalProperties: false,
                required: ['ok', 'summary', 'command', 'errorCount', 'warningCount', 'notes'],
                properties: {
                    ok: { type: 'boolean' },
                    summary: { type: 'string' },
                    command: { type: 'string' },
                    target: { type: 'string' },
                    scheme: { type: 'string' },
                    destination: { type: 'string' },
                    exitCode: { type: 'integer' },
                    errorCount: { type: 'integer' },
                    warningCount: { type: 'integer' },
                    diagnostics: { type: 'string' },
                    outputTail: { type: 'string' },
                    notes: {
                        type: 'array',
                        items: { type: 'string' },
                    },
                },
            },
            render(_args, value) {
                // The structured `notes` array is part of the declared output, but the
                // model only ever sees these content blocks — so anything it must act on
                // (which scheme was auto-selected, a warnings-are-fatal verdict, a
                // timeout, dropped output) has to be rendered here or it is invisible.
                const notes = Array.isArray(value.notes) ? value.notes.filter(isNonEmptyString) : [];
                const parts = [
                    value.summary,
                    value.diagnostics,
                    notes.length > 0 ? `Notes:\n${notes.map((note) => `- ${note}`).join('\n')}` : undefined,
                    value.outputTail,
                ].filter(isNonEmptyString);
                const text = parts.join('\n\n');
                return [textBlock(text.length > 0 ? text : 'xcodebuild finished with no output')];
            },
        },
        async execute(args, exec) {
            const cwd = resolveCwd(config, args.cwd);
            const notes = [];
            const started = Date.now();
            let target = isNonEmptyString(args.target) ? args.target.trim() : undefined;
            let scheme = isNonEmptyString(args.scheme) ? args.scheme.trim() : undefined;
            if (target === undefined || scheme === undefined) {
                const discovered = await discoverProject(ctx, config, cwd);
                if (discovered.detectionLog.length > 0)
                    notes.push(discovered.detectionLog);
                if (target === undefined) {
                    target = discovered.target;
                    if (target !== undefined)
                        notes.push(`auto-discovered target: ${target}`);
                }
                if (scheme === undefined) {
                    if (discovered.schemes.length === 1) {
                        scheme = discovered.schemes[0];
                        notes.push(`auto-selected the only scheme: ${scheme}`);
                    }
                    else if (discovered.schemes.length > 1) {
                        // A one-click build must not stall on a multi-scheme project. Prefer
                        // the scheme that names the target itself — Xcode's convention is
                        // that the app target's scheme matches the project/workspace name,
                        // and only when nothing matches is a human choice really required.
                        const preferred = target !== undefined ? preferredScheme(discovered.schemes, target) : undefined;
                        if (preferred !== undefined) {
                            scheme = preferred;
                            notes.push(`auto-selected scheme: ${scheme} (matches ${target}); ` +
                                `pass \`scheme\` to build another one of: ${discovered.schemes.join(', ')}`);
                        }
                        else {
                            return {
                                ok: false,
                                summary: `No scheme matches ${target}. Pass \`scheme\` explicitly. ` +
                                    `Available: ${discovered.schemes.join(', ')}`,
                                command: 'xcodebuild -list',
                                errorCount: 0,
                                warningCount: 0,
                                notes,
                            };
                        }
                    }
                }
                if (discovered.diagnostics.length > 0)
                    notes.push(bounded(discovered.diagnostics, 2000).text);
            }
            if (target === undefined) {
                return {
                    ok: false,
                    summary: `No .xcworkspace or .xcodeproj found in ${cwd}. Pass \`target\` explicitly.`,
                    command: 'xcodebuild',
                    errorCount: 0,
                    warningCount: 0,
                    notes,
                };
            }
            const action = isNonEmptyString(args.action) ? args.action.trim() : 'build';
            const configuration = isNonEmptyString(args.configuration) ? args.configuration.trim() : 'Debug';
            const flag = target.endsWith('.xcworkspace') ? '-workspace' : '-project';
            const argv = [config.xcodebuildPath, action, flag, target];
            if (scheme !== undefined)
                argv.push('-scheme', scheme);
            let destination = isNonEmptyString(args.destination) ? args.destination.trim() : undefined;
            const needsDestination = action !== 'clean' && action !== 'build-for-testing';
            if (destination === undefined && needsDestination) {
                const simulator = isNonEmptyString(args.simulator) ? args.simulator.trim() : undefined;
                const os = isNonEmptyString(args.os) ? args.os.trim() : undefined;
                if (simulator !== undefined) {
                    destination =
                        os !== undefined
                            ? `platform=iOS Simulator,name=${simulator},OS=${os}`
                            : `platform=iOS Simulator,name=${simulator}`;
                }
            }
            if (destination !== undefined)
                argv.push('-destination', destination);
            if (Array.isArray(args.only_testing)) {
                for (const entry of args.only_testing) {
                    if (isNonEmptyString(entry))
                        argv.push('-only-testing', entry.trim());
                }
            }
            if (isNonEmptyString(args.derived_data_path)) {
                argv.push('-derivedDataPath', args.derived_data_path.trim());
            }
            if (Array.isArray(args.extra_args)) {
                for (const entry of args.extra_args) {
                    if (isNonEmptyString(entry))
                        argv.push(entry);
                }
            }
            const result = await runCommand(ctx, config, {
                argv,
                cwd,
                timeoutMs: config.buildTimeoutMs,
                ...(exec.signal !== undefined ? { signal: exec.signal } : {}),
            });
            const command = argv.join(' ');
            const diagnostics = parseDiagnostics(result.output, config.maxDiagnostics);
            const errorCount = diagnostics.filter((item) => item.severity === 'error').length;
            const warningCount = diagnostics.filter((item) => item.severity === 'warning').length;
            const tail = boundedTail(result.output, config.maxOutputChars);
            if (result.unavailable) {
                return {
                    ok: false,
                    summary: result.output,
                    command,
                    target,
                    ...(scheme !== undefined ? { scheme } : {}),
                    errorCount: 0,
                    warningCount: 0,
                    notes,
                };
            }
            if (result.timedOut)
                notes.push(`xcodebuild exceeded ${config.buildTimeoutMs} ms and was terminated`);
            if (result.lossy)
                notes.push('build output overflowed the in-memory budget and some output was dropped');
            if (result.exitCode !== 0 && diagnostics.length === 0) {
                notes.push('xcodebuild exited nonzero but no diagnostic line matched; the cause is in the output tail below');
            }
            const warningsAreFatal = config.treatWarningsAsErrors && warningCount > 0;
            if (warningsAreFatal) {
                notes.push('this project treats compiler warnings as failures (treatWarningsAsErrors); ' +
                    'set treatWarningsAsErrors: false in the plugin config to relax it');
            }
            const ok = result.exitCode === 0 && errorCount === 0 && !warningsAreFatal && !result.timedOut;
            const elapsed = Math.round((Date.now() - started) / 1000);
            const verdict = ok
                ? `xcodebuild ${action} succeeded in ${elapsed}s`
                : result.timedOut
                    ? `xcodebuild ${action} was terminated after ${config.buildTimeoutMs} ms`
                    : `xcodebuild ${action} failed (exit ${result.exitCode ?? result.signal ?? 'unknown'}) after ${elapsed}s`;
            const counts = `${errorCount} error(s), ${warningCount} warning(s) parsed`;
            return {
                ok,
                summary: `${verdict} — ${counts}`,
                command,
                target,
                ...(scheme !== undefined ? { scheme } : {}),
                ...(destination !== undefined ? { destination } : {}),
                ...(result.exitCode !== null ? { exitCode: result.exitCode } : {}),
                errorCount,
                warningCount,
                ...(diagnostics.length > 0 ? { diagnostics: formatDiagnostics(diagnostics) } : {}),
                outputTail: `--- last ${config.maxOutputChars} chars of build output ---\n${tail.text}`,
                notes,
            };
        },
    });
    register({
        name: 'xcode_info',
        description: 'Inspect the Xcode project next to the current directory: the workspace/project path and its ' +
            'schemes and configurations, plus the available simulator runtimes. Call this before a first ' +
            '`xcode_build` when you do not know the scheme name.',
        isConcurrencySafe: () => true,
        timeoutMs: 180000,
        parameters: {
            type: 'object',
            properties: {
                cwd: { type: 'string', description: 'Directory to inspect. Defaults to the plugin working directory.' },
            },
        },
        output: {
            schema: {
                type: 'object',
                additionalProperties: false,
                required: ['ok', 'summary', 'schemes', 'configurations', 'runtimes', 'notes'],
                properties: {
                    ok: { type: 'boolean' },
                    summary: { type: 'string' },
                    target: { type: 'string' },
                    schemes: { type: 'array', items: { type: 'string' } },
                    configurations: { type: 'array', items: { type: 'string' } },
                    runtimes: { type: 'array', items: { type: 'string' } },
                    notes: { type: 'array', items: { type: 'string' } },
                },
            },
            render(_args, value) {
                return [textBlock(value.summary)];
            },
        },
        async execute(args) {
            const cwd = resolveCwd(config, args.cwd);
            const notes = [];
            const discovered = await discoverProject(ctx, config, cwd);
            const runtimes = await runCommand(ctx, config, {
                argv: [config.xcrunPath, 'simctl', 'list', 'runtimes', '-j'],
                cwd,
                timeoutMs: config.simctlTimeoutMs,
            });
            const runtimeNames = [];
            const runtimesDocument = parseJsonObject(runtimes.output);
            if (runtimesDocument === undefined) {
                if (runtimes.output.trim().length > 0)
                    notes.push('could not parse `simctl list runtimes -j` output');
            }
            else {
                const list = runtimesDocument.runtimes;
                for (const runtime of Array.isArray(list) ? list : []) {
                    if (runtime.isAvailable === false)
                        continue;
                    const name = String(runtime.name ?? '');
                    const version = String(runtime.version ?? '');
                    runtimeNames.push(version.length > 0 ? `${name} (${version})` : name);
                }
            }
            if (discovered.schemes.length === 0)
                notes.push('no schemes were discovered');
            const lines = [
                `target: ${discovered.target ?? '(none found in ' + cwd + ')'}`,
                `schemes: ${discovered.schemes.length > 0 ? discovered.schemes.join(', ') : '(none)'}`,
                `runtimes: ${runtimeNames.length > 0 ? runtimeNames.join(', ') : '(none)'}`,
            ];
            if (discovered.diagnostics.length > 0)
                notes.push(bounded(discovered.diagnostics, 1500).text);
            return {
                ok: discovered.target !== undefined,
                summary: lines.join('\n'),
                ...(discovered.target !== undefined ? { target: discovered.target } : {}),
                schemes: discovered.schemes,
                configurations: ['Debug', 'Release'],
                runtimes: runtimeNames,
                notes,
            };
        },
    });
    // ---------------------------------------------------------------------------
    // Capability 2: Simulator control
    // ---------------------------------------------------------------------------
    register({
        name: 'simulator_control',
        description: 'Control iOS simulators through `xcrun simctl`: boot, shutdown, list devices, and inspect the ' +
            'currently booted device. `open` also brings the Simulator app to the front. Destructive ' +
            'actions (`erase`, `delete`) require `confirm: true`.',
        isConcurrencySafe: () => false,
        timeoutMs: config.simctlTimeoutMs + 30000,
        parameters: {
            type: 'object',
            properties: {
                action: {
                    type: 'string',
                    enum: ['list', 'boot', 'shutdown', 'booted', 'open', 'erase', 'delete', 'runtime_list'],
                    description: 'The simctl operation to perform.',
                },
                device: {
                    type: 'string',
                    description: 'Simulator name, UDID, or `booted`. Defaults to the booted device where meaningful.',
                },
                runtime: {
                    type: 'string',
                    description: 'Runtime substring filter for `list`, e.g. `iOS-27`. Only available devices are shown.',
                },
                confirm: {
                    type: 'boolean',
                    description: 'Must be true for the destructive `erase` and `delete` actions.',
                },
                cwd: { type: 'string', description: 'Directory to run in. Defaults to the plugin working directory.' },
            },
            required: ['action'],
        },
        output: {
            schema: {
                type: 'object',
                additionalProperties: false,
                required: ['ok', 'action', 'summary', 'notes'],
                properties: {
                    ok: { type: 'boolean' },
                    action: { type: 'string' },
                    summary: { type: 'string' },
                    device: { type: 'string' },
                    udid: { type: 'string' },
                    exitCode: { type: 'integer' },
                    notes: { type: 'array', items: { type: 'string' } },
                },
            },
            render(_args, value) {
                return [textBlock(value.summary)];
            },
        },
        async execute(args) {
            const cwd = resolveCwd(config, args.cwd);
            const action = isNonEmptyString(args.action) ? args.action.trim() : 'list';
            const notes = [];
            const run = (argv) => runCommand(ctx, config, { argv: [config.xcrunPath, 'simctl', ...argv], cwd, timeoutMs: config.simctlTimeoutMs });
            if (action === 'list') {
                const runtimeFilter = isNonEmptyString(args.runtime) ? args.runtime.trim() : undefined;
                const listed = await run(['list', 'devices', 'available', '-j']);
                if (listed.unavailable)
                    return { ok: false, action, summary: listed.output, notes };
                const document = parseJsonObject(listed.output);
                if (document === undefined)
                    return { ok: false, action, summary: bounded(listed.output, 4000).text, notes };
                return { ok: true, action, summary: formatDevices(document, runtimeFilter), notes };
            }
            if (action === 'runtime_list') {
                const listed = await run(['list', 'runtimes']);
                return {
                    ok: listed.exitCode === 0,
                    action,
                    summary: bounded(listed.output, 4000).text,
                    notes,
                };
            }
            if (action === 'booted') {
                const resolved = await resolveDevice(ctx, config, cwd, undefined);
                if (resolved.udid === undefined) {
                    return { ok: false, action, summary: resolved.note ?? 'no booted simulator', notes };
                }
                const described = await run(['list', 'devices', 'booted', '-j']);
                const document = parseJsonObject(described.output);
                let label = resolved.udid;
                if (document !== undefined) {
                    const device = Object.values(deviceGroups(document)).flat()[0];
                    if (device !== undefined)
                        label = `${String(device.name)} [${String(device.state)}] ${resolved.udid}`;
                }
                return { ok: true, action, summary: `booted device: ${label}`, udid: resolved.udid, notes };
            }
            if ((action === 'erase' || action === 'delete') && args.confirm !== true) {
                return {
                    ok: false,
                    action,
                    summary: `\`${action}\` is destructive; pass confirm: true to proceed`,
                    notes,
                };
            }
            const resolved = await resolveDevice(ctx, config, cwd, args.device);
            if (resolved.udid === undefined) {
                return { ok: false, action, summary: resolved.note ?? 'no matching simulator', notes };
            }
            const udid = resolved.udid;
            if (action === 'open') {
                // `open -a Simulator` only fronts the UI; boot the device first so the
                // window actually shows this simulator.
                await run(['boot', udid]);
                const opened = await runCommand(ctx, config, {
                    argv: ['/usr/bin/open', '-a', 'Simulator'],
                    cwd,
                    timeoutMs: 30000,
                });
                if (opened.exitCode !== 0)
                    notes.push(bounded(opened.output, 500).text);
                return {
                    ok: opened.exitCode === 0,
                    action,
                    summary: `opened Simulator with ${udid}`,
                    udid,
                    ...(opened.exitCode !== null ? { exitCode: opened.exitCode } : {}),
                    notes,
                };
            }
            const simctlAction = action === 'boot' ? 'boot' : action;
            const result = await run([simctlAction, udid]);
            // Booting an already-booted device reports a benign "Unable to boot device
            // in current state: Booted"; treat that as success.
            const alreadyBooted = /current state:\s*Booted/i.test(result.output);
            if (alreadyBooted)
                notes.push('device was already in the requested state');
            const ok = result.exitCode === 0 || alreadyBooted;
            const summary = bounded(ok
                ? `${action} ${udid}: ${result.output.trim().length > 0 ? result.output.trim() : 'ok'}`
                : `${action} ${udid} failed: ${result.output.trim()}`, 3000).text;
            return {
                ok,
                action,
                summary,
                udid,
                ...(result.exitCode !== null ? { exitCode: result.exitCode } : {}),
                notes,
            };
        },
    });
    register({
        name: 'simulator_install_launch',
        description: 'Install a built `.app` bundle onto a simulator and launch it (`xcrun simctl install` + `launch`). ' +
            'Pass the `.app` product from an `xcode_build` run; `bundle_id` is required for launching and is ' +
            'optional when only installing.',
        isConcurrencySafe: () => false,
        timeoutMs: config.simctlTimeoutMs + 30000,
        parameters: {
            type: 'object',
            properties: {
                app_path: { type: 'string', description: 'Path to the built `.app` bundle.' },
                bundle_id: { type: 'string', description: 'Bundle identifier to launch, e.g. com.example.app.' },
                device: { type: 'string', description: 'Simulator name, UDID, or `booted`. Defaults to the booted device.' },
                launch: { type: 'boolean', description: 'Launch after installing. Defaults to true when bundle_id is given.' },
                terminate_existing: {
                    type: 'boolean',
                    description: 'Terminate a running instance before launching. Defaults to false.',
                },
                console: {
                    type: 'boolean',
                    description: 'Stream the app console to stdout via `launch --console-pty`. Defaults to false.',
                },
                arguments: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Launch arguments passed to the app.',
                },
                cwd: { type: 'string', description: 'Directory to run in. Defaults to the plugin working directory.' },
            },
            required: ['app_path'],
        },
        output: {
            schema: {
                type: 'object',
                additionalProperties: false,
                required: ['ok', 'summary', 'appPath', 'notes'],
                properties: {
                    ok: { type: 'boolean' },
                    summary: { type: 'string' },
                    appPath: { type: 'string' },
                    bundleId: { type: 'string' },
                    udid: { type: 'string' },
                    pid: { type: 'integer' },
                    notes: { type: 'array', items: { type: 'string' } },
                },
            },
            render(_args, value) {
                return [textBlock(value.summary)];
            },
        },
        async execute(args) {
            const cwd = resolveCwd(config, args.cwd);
            const notes = [];
            if (!isNonEmptyString(args.app_path)) {
                return { ok: false, summary: 'app_path is required', appPath: '', notes };
            }
            const appPath = args.app_path.trim();
            const bundleId = isNonEmptyString(args.bundle_id) ? args.bundle_id.trim() : undefined;
            const shouldLaunch = args.launch === false ? false : bundleId !== undefined;
            if (shouldLaunch && bundleId === undefined) {
                return { ok: false, summary: 'bundle_id is required to launch the app', appPath, notes };
            }
            const resolved = await resolveDevice(ctx, config, cwd, args.device);
            if (resolved.udid === undefined) {
                return { ok: false, summary: resolved.note ?? 'no matching simulator', appPath, notes };
            }
            const udid = resolved.udid;
            // Install and launch both require a booted device.
            const booted = await runCommand(ctx, config, {
                argv: [config.xcrunPath, 'simctl', 'boot', udid],
                cwd,
                timeoutMs: config.simctlTimeoutMs,
            });
            if (booted.exitCode !== 0 && !/current state:\s*Booted/i.test(booted.output)) {
                notes.push(`boot reported: ${bounded(booted.output, 300).text}`);
            }
            const installed = await runCommand(ctx, config, {
                argv: [config.xcrunPath, 'simctl', 'install', udid, appPath],
                cwd,
                timeoutMs: config.simctlTimeoutMs,
            });
            if (installed.exitCode !== 0) {
                return {
                    ok: false,
                    summary: `install failed: ${bounded(installed.output, 3000).text}`,
                    appPath,
                    udid,
                    ...(bundleId !== undefined ? { bundleId } : {}),
                    notes,
                };
            }
            const lines = [`installed ${appPath} on ${udid}`];
            if (!shouldLaunch || bundleId === undefined) {
                return { ok: true, summary: lines.join('\n'), appPath, udid, notes };
            }
            if (args.terminate_existing === true) {
                await runCommand(ctx, config, {
                    argv: [config.xcrunPath, 'simctl', 'terminate', udid, bundleId],
                    cwd,
                    timeoutMs: config.simctlTimeoutMs,
                });
            }
            const launchArgv = [config.xcrunPath, 'simctl', 'launch'];
            if (args.console === true)
                launchArgv.push('--console-pty');
            launchArgv.push(udid, bundleId);
            if (Array.isArray(args.arguments)) {
                for (const entry of args.arguments) {
                    if (isNonEmptyString(entry))
                        launchArgv.push(entry);
                }
            }
            const launched = await runCommand(ctx, config, {
                argv: launchArgv,
                cwd,
                timeoutMs: args.console === true ? config.simctlTimeoutMs * 4 : config.simctlTimeoutMs,
            });
            const pidMatch = /:\s*(\d+)\s*$/.exec(launched.output.trim());
            const pid = pidMatch !== null ? Number(pidMatch[1]) : undefined;
            const ok = launched.exitCode === 0 || pid !== undefined;
            lines.push(ok
                ? `launched ${bundleId}${pid !== undefined ? ` (pid ${pid})` : ''}`
                : `launch failed: ${bounded(launched.output, 2000).text}`);
            return {
                ok,
                summary: lines.join('\n'),
                appPath,
                bundleId,
                udid,
                ...(pid !== undefined ? { pid } : {}),
                notes,
            };
        },
    });
    // ---------------------------------------------------------------------------
    // Capability 3: SwiftUI guidance in the system prompt
    // ---------------------------------------------------------------------------
    if (config.injectSwiftUIGuidance) {
        // Place the guidance one slot after the deployment persona: it is a
        // project convention, so it precedes the per-tool sections (TOOL_BASH at
        // 1000) and follows the identity/persona text. `+1` only needs to keep a
        // stable relative position, never an absolute number.
        const order = ctx.systemPrompt.getSectionOrder('DEPLOYMENT_PERSONA_PREFIX') + 1;
        disposers.push(ctx.systemPrompt.section({
            name: 'ios-dev-helper/swiftui',
            order,
            // Drop the section entirely when this plugin's tools are hidden from the
            // viewing scope, so prompt and tool surface never disagree.
            text: ({ scope }) => ctx.tools.get('xcode_build', scope) === undefined ? '' : SWIFTUI_GUIDANCE,
        }));
    }
    // Cordis disposes effect-owned registrations on unload; returning the same
    // cleanup keeps teardown explicit and idempotent.
    return () => {
        for (const dispose of disposers.splice(0).reverse()) {
            try {
                dispose();
            }
            catch {
                // A registration already removed by scope teardown must not break unload.
            }
        }
    };
}
