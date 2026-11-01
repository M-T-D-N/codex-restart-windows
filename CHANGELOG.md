# Changelog

## 0.1.0-preview.1

Initial standalone Windows source preview.

- Add a user-armed, independent interactive-user Task Scheduler worker.
- Bind old/new process identities and worker/core/launcher/image hashes.
- Consume one persistent operation claim before at-most-one launch dispatch.
- Preserve cancellation, timeout, refusal and unconfirmed launch results.
- Remove only the exact owned registration; leave the ordinary taskbar launch
  and app data unchanged.
- Include Windows PowerShell 5.1/PowerShell 7 source checks, seven actual
  Scheduler/synthetic-process scenarios, bilingual README and recovery guidance.

This preview has no DB/WAL backup, AM integration, forced Quit, automatic retry,
fallback version or update feature. Real Codex GUI and fresh-PC acceptance of
this standalone package remain unverified. See [validation](docs/validation.md).
