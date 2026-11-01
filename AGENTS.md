# Codex Restart for Windows

- Follow the owning workspace's routing instructions when present; this public repository has no machine-specific workspace dependency.
- This repository owns a standalone, user-armed Windows restart coordinator. Ares, installed Codex, authentication, conversations and AgentMemory are separate owners.
- Use `powershell.exe -NoProfile -File tests/run.ps1 -ScratchRoot <absolute-owned-path>` for synthetic checks. Scheduler integration is a separate explicit test.
- Never stop real Codex or another user's process to run tests. Test fixtures own their paths and exit naturally.
- Public files must contain no private paths, operating plans, process receipts, credentials, databases or actual conversations.
- A successful process observation is not proof of GUI readiness, backend cleanup or a completed model request. Preserve failed and unknown results.
- Keep the ordinary taskbar launch unchanged. No force termination, elevation, execution-policy changes, automatic retries or rollback launches.
