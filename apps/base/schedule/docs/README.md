# base/schedule

Base Schedule owns installation-global recurrence registration, intended-
occurrence claiming, suppression, and best-effort operational run history. It
does not own business retries or business idempotency. The capability that
contributes a definition owns its `Bilimbi.Base.Schedule.Worker` and durable
business result; Base Queue owns transport and retry.

Definitions are immutable `:schedule` contributions discovered in the one
ModuleRegistry snapshot. Provider order is the validated dependency-first
descriptor order. A definition declares an explicit durable key, five-field
cron expression, IANA timezone, task name, capability-owned worker, bounded
plain arguments, overlap policy, and the currently supported `:coalesce`
misfire policy. A contributor may also declare an internal owner route so the
operator board can link back to the capability that owns the task without
making the definition editable in Base Schedule. No topology glob,
environment provider list, reflection scan, or second dependency graph
participates.

## Time and delivery

The scheduler resolves the most recent local wall-clock occurrence at each
poll. During ordinary operation both sides of a repeated DST time can run;
nonexistent spring-forward times do not. After downtime only the latest missed
occurrence is considered. A unique Bilimbi-only occurrence row and its Oban
job commit in one transaction, so competing nodes cannot enqueue the same UTC
intended occurrence twice. `:forbid` overlap also holds one active database
lease until the worker succeeds, is cancelled, or exhausts retries. Schedule
reconciles that lease from Queue's bounded terminal state before a new claim
and on every recurrence poll, including direct cancellation,
unavailable-worker discard, and a Queue row pruned after terminal completion.

Queue remains at-least-once. Schedule's occurrence claim prevents duplicate
enqueue, not duplicate business effects after worker failure. Workers must
enforce their own durable idempotency. Manual run-now resolves the same
definition, review, suppression, overlap, Queue, and recording path and never
executes inline.

Every new definition, or a definition whose material fingerprint changes, is
disabled until explicitly reviewed. This is deliberate for both fresh and
adopted installations: an unmatched historical suppression or renamed key can
never silently enable work. A suppression row continues to mean paused, and
deleting it means resumed. Suppression/review read uncertainty fails closed.
The exact reviewed fingerprint and suppression state are checked again when a
queued job starts. Pausing, disabling, removing, or materially changing a
definition therefore cancels work that has not begun; work already executing
remains subject to its capability-owned idempotency and cancellation policy.

## Compatibility and history

`base_schedule_runs` and `base_schedule_suppressions` are exact compatible
Belimbing baselines. Existing run rows remain operational evidence, and
existing suppressions must be mapped to explicit new durable keys during
cutover. Removed definitions intentionally leave orphan history and
suppressions for operator disposition. Laravel queue relations and payloads
remain inert and are never translated.

The occurrence and definition-review relations are Bilimbi-only runtime state
and are never adopted as compatible migrations. Run history is best effort:
recorder or retention failure is logged with only bounded source/key facts and
cannot reverse committed business work. `schedule.history.keep_days` is global,
defaults to 90, accepts the operational range 0..3650, and treats zero as
pruning disabled. Pruning is opportunistic at capability-worker start, avoiding
a recurrence that depends on the scheduler to prune the scheduler itself.

Rollback must first stop all Bilimbi producers and workers. The migrations
refuse to discard non-empty history, suppression, occurrence, or review state.
Export or explicitly disposition those rows before rolling back within the
agreed window; restoring Laravel does not make its inert jobs executable in
Bilimbi.

The runtime contributes installation-global `admin.system.schedule.view`,
`.execute`, and `.manage` capabilities. The Schedule operator board keeps
these capabilities distinct: view reads bounded task, history, and diagnostic
facts; execute queues run-now; manage reviews definitions, pauses or resumes
them, and changes retention. Every handler re-authorizes against current Authz
state. Successful operator commands and their actor are recorded through Base
Audit in the same transaction as the controlled state change; operational run
rows remain separate best-effort evidence.

History filtering, ordering, exact totals, and pagination happen in PostgreSQL
before rows reach the LiveView. Worker arguments and recorded output excerpts
never cross the operator-facing Schedule API. Diagnostics report scheduler,
Queue, recorder, and due-work evidence independently, using unknown or
unavailable states rather than deriving health from missing rows.
