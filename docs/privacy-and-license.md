# Privacy, provenance and license

## Local records

The runtime makes no network or model request and collects no conversation or
authentication data. It writes an operation plan/result, a persistent claim and
optional cancellation/error sidecars in the user-selected directory. It also
registers a temporary Task Scheduler entry.

Plans contain local paths, a Windows SID/session, process metadata, SHA-256
hashes, and **launcher arguments in clear text**. Results contain process
identities and timestamps. The process command line is queried locally but
stored as a SHA-256 hash rather than raw text. Your launcher can have its own
network/logging behavior; this tool cannot constrain it.

Treat the entire operation directory as private. Do not commit/upload it or pass
credentials as arguments. Before reporting an issue, redact usernames, paths,
SIDs, arguments and any data from your own launcher. Share only needed error
codes, stages, tool commit and sanitized reproduction steps. Existing OS task
history is governed by Windows; this tool does not erase it.

## Source and attribution

The scripts and documentation are licensed under [MIT](../LICENSE). Preserve
the copyright and permission notice in copies/substantial portions. The license
does not provide a warranty; it does not grant rights to third-party software.

Identity binding, independent launch and a persistent one-shot claim were
adapted from locally authored Ares restart work. That environment-specific
helper was not an Ares public product component. Its database/WAL backup,
memory, tunnel, private paths and operating receipts are **not included** here.
The standalone coordinator is a new, separately tested implementation; earlier
Ares success is not reused as proof that this package restarts Codex correctly.

No OpenAI/Codex source, desktop/native binary, runtime, private database, actual
chat or credential is redistributed. Windows APIs and installed PowerShell are
external prerequisites, not bundled components. The integration test compiles
its own small C# fixture locally and never includes that binary in a release.
The optional example activates an already-installed app; it neither downloads
nor licenses that app. OpenAI and Codex names identify compatibility intent,
not endorsement or affiliation.

## Publication contents

`publication-files.json` is the source-file allowlist. The publication check
compares tracked files with this list, checks local document links and scans
for selected private-path/credential signatures. It is a targeted check, not a
proof that arbitrary future content contains no secret; human diff review is
still required. Tests' private scratch logs and fixtures stay outside the ZIP.

Release assets contain source files plus checksums, not operating plans or
runtime packages. CI links in the Release refer to the exact source commit.
