## Environment & WSL2 Execution Rules
1. **WSL2 Paths:** Always set command `Cwd` to native Windows (`C:\Users\user1` or `C:\`) when calling `wsl.exe`. Inside bash, `cd` to the absolute Linux worktree path (e.g. `/home/kiat/repo/bilimbi-...`). Never run `wsl.exe` from a `Z:\` path.
2. **Mise Shims:** Always prefix Mix/Elixir commands with `export PATH="$HOME/.local/share/mise/shims:$PATH"`.

## Background Tasks & Scheduling Rules
1. **No Polling Loops in Shell:** Never run infinite `while true; sleep ...` loops in bash commands. All commands must execute a bounded task and exit with code 0/1.
2. **Single Heartbeat Daemon:** Set the heartbeat cron schedule (`schedule` tool with `CronExpression`) **only once** with `IsDaemon: true`. Do not spawn multiple timers or stack cron jobs.
3. **Synchronous Execution by Default:** Set `WaitMsBeforeAsync: 10000` (or sufficient time) so tests, builds, and `gh` CLI commands complete synchronously rather than leaking into unmonitored background tasks.
4. **Reactive Wakeup:** When a task does run in the background, do not poll `manage_task(Action: 'status')` in a loop. Stop calling tools and let the system notify you reactively upon task completion.
5. **Clean Up Tasks:** Before starting a new long-running task, check and terminate stale tasks with `manage_task(Action: 'kill')` if any linger.