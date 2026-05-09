# Building a Resilient, Highly-Available Reminder + Alarm App

This document is the teaching companion to the code in this repo. It walks through the
why behind every reliability decision, the trade-offs, and the limitations we accept.
The companion code is split across `ios/` (SwiftUI client), `server/` (Vapor backend)
and `infra/` (Fly.io deployment). Read this once before reading the code; everything
else will make more sense.

---

## 1. What "resilient, highly-available, reliable" actually means here

These three words sound similar but mean different things, and the design choices
hinge on the difference.

| Word | Definition we use | Concrete failure mode it answers |
|---|---|---|
| **Reliable** | The right alarm rings at (or close to) the right time. | A user trusts the app to wake them up. |
| **Highly available** | The system keeps serving requests even when individual machines fail. | A backend instance crashes; users keep editing reminders. |
| **Resilient** | When something does break, the system recovers without lost data and without manual intervention. | Network drops mid-sync; a push fails; the user reinstalls the app. |

For an alarm app the **most user-visible** dimension is reliability of the alarm
itself. The user does not care that we have nine 9s of API uptime if their alarm
did not ring. So our top priority is the *delivery path of a single notification*,
not API uptime.

## 2. The core architectural decision: dual-channel delivery

Push notifications over APNs are **best-effort**. Apple does not guarantee
delivery, ordering, or precise timing. They can be silently dropped if the device
is offline, in Low Power Mode, or in certain Focus configurations. A backend that
relies only on APNs would have a single point of failure that we don't even
control.

**Local notifications**, scheduled on-device with `UNUserNotificationCenter`, are
the opposite: they are scheduled into the OS's local timer, fire even with the
device offline / airplane mode / backend down, and survive app suspension. But
they do *not* survive app reinstall, can drift if the user changes the device
clock, and do not propagate across the user's devices.

Each channel's weakness is the other's strength, so we use **both**:

```
                 ┌─────────────────┐
   Reminder ────▶│  Local schedule │──▶ UN center fires at due_at  ◀── primary path
                 └─────────────────┘
                          │
                          ▼ also synced to
                 ┌─────────────────┐
                 │     Backend     │──▶ APNs push at due_at        ◀── backup path
                 └─────────────────┘
```

The client de-duplicates by `(reminderId, occurrenceEpoch)` so the user only sees
one alert even when both fire within seconds of each other.

This is the single most important idea in the system. Everything else exists to
support it.

## 3. Client architecture (iOS)

We extend the existing `TaskReminder` SwiftUI app rather than rewriting it. The
existing code is already structured into Models / ViewModels / Services / Views,
which makes it easy to bolt on new behavior with dependency injection.

### 3.1 Reuse via the `TaskStoring` protocol

The existing `TaskViewModel` accepts any `TaskStoring`-conforming store via its
initializer. We exploit that by introducing a **decorator**:

```
TaskViewModel ─▶ SyncableTaskStore ─▶ TaskStore (existing JSON file)
                       │
                       └─▶ SyncQueue ─▶ SyncEngine ─▶ APIClient ─▶ Server
```

`SyncableTaskStore` implements `TaskStoring`, persists to the inner `TaskStore`
exactly as before (so the app keeps working offline), and additionally records a
delta into `SyncQueue` (`sync_queue.json`). A background `SyncEngine` actor
drains the queue against the server with retry and idempotency keys, and pulls
remote changes in the same pass.

Why a decorator and not a rewrite? Two reasons:
1. The existing UI and ViewModel paths stay untouched, so the entire offline
   experience is verified by the fact that the app still launches and works.
2. If the sync layer is ever broken, we can swap `SyncableTaskStore` back to
   plain `TaskStore` in one line and ship.

### 3.2 Offline-first writes

Every mutation is committed locally first. The `SyncQueue` only describes
*intent to sync*. A user with no network can:
- Create, edit, delete reminders.
- Have reminders ring on time (local notifications were already scheduled).
- Come back online hours later; the queue drains in the order ops were recorded.

This is also how we get **resilience**: a brief network blip does not corrupt
state, because the user's edits are durable on disk before any network call is
attempted.

### 3.3 The audible alarm path

We were honest with the user up front: a real "alarm-clock" experience on iOS
(rings past 30 seconds, ignores the silent switch, bypasses Focus / Do Not
Disturb) requires the **Critical Alerts entitlement**, which Apple grants by
application and rarely approves for productivity apps. Without it, the OS caps
each notification's sound to the duration of its `.caf` file (max ~30s), and the
silent switch silences sound entirely.

We do as much as possible without the entitlement and leave the door open:

- A custom `.caf` of ~28 seconds (`alarm_long.caf`) gives us the longest
  permitted single ring.
- We schedule **three chained notifications** at `dueDate + 0s`, `+32s`, `+64s`
  using the same `threadIdentifier`. The user gets ~90 seconds of
  intermittent ringing instead of one short ring.
- `interruptionLevel = .timeSensitive` gets us through Focus modes that allow
  time-sensitive interruptions, which is the next-best thing to bypassing them.
- A feature flag `FeatureFlags.criticalAlertsEnabled` is wired through. The day
  Apple grants the entitlement, flipping the flag swaps the sound to
  `UNNotificationSound.defaultCriticalSound(withAudioVolume:)` everywhere with
  no other code changes.

The user picks `standard` or `loud` per reminder; the server stores the choice
so it propagates to the user's other devices.

### 3.4 Sign in with Apple

We use Sign in with Apple end-to-end:
- The client uses `ASAuthorizationAppleIDProvider` and generates a SHA-256 nonce
  per attempt to prevent replay.
- It posts the resulting identity token to `POST /auth/apple`.
- The server **verifies the identity token's signature** against Apple's JWKS
  (`https://appleid.apple.com/auth/keys`), checks `iss`, `aud=APPLE_BUNDLE_ID`,
  `exp`, and the nonce, then issues a short-lived backend JWT (15 min, ES256)
  plus an opaque refresh token (30 days, hashed at rest, rotated on each use).
- Tokens are stored in the iOS Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they're encrypted at
  rest and never sync to other devices via iCloud Keychain.

Why Sign in with Apple? Because it gives us account recovery and multi-device
sync without owning password storage, password reset flows, or email delivery.
The user's email may even be Apple's relay address — we treat that as
intentional and never require email for any flow.

## 4. Server architecture (Vapor)

The server's job is small but specific:

1. Authenticate users (Sign in with Apple → backend JWT).
2. Provide CRUD + sync for reminders.
3. Track the user's devices (APNs tokens).
4. **Fire APNs pushes when reminders come due**, as the backup channel.

### 4.1 The data model and sync contract

Sync is an evergreen source of bugs, so we picked the simplest contract that
correctly handles concurrent edits:

- Client-generated UUIDs. The client never has to wait for a server-assigned id
  to keep working offline.
- Last-writer-wins keyed on `(updated_at, version)`. Every update bumps
  `version` and the server stamps a fresh `updated_at`.
- Tombstones, not hard deletes. Deleting a row sets `deleted_at`; we keep
  tombstones for 30 days so other devices that have been offline can converge.
- `GET /reminders?since=cursor` for incremental pull; the cursor is the
  high-water mark of `updated_at` the client has seen.
- `PUT /reminders/{id}` and `POST /reminders/batch` are **idempotent**: clients
  send an `Idempotency-Key` header and we cache `(key, userId) → response` for
  24 hours. Replays return the original response, so a flaky network on the
  client cannot create duplicates.

We deliberately did *not* reach for CRDTs. Reminders are tiny, conflict-free in
practice (two devices rarely edit the same field at the same second), and LWW
is something every developer can reason about at 3am.

### 4.2 The outbox pattern

The single most common bug in "send a notification when X happens" systems is
the dual-write problem: `INSERT row` succeeds, `enqueue push` fails, the row
exists but no notification ever fires. The fix is the **outbox pattern**:

```
BEGIN;
INSERT INTO reminders (...);
INSERT INTO outbox_events (kind='reminder_created', payload, ...);
COMMIT;
```

Both rows commit together or neither does. A separate worker reads the outbox
and dispatches APNs pushes. If the worker crashes, the outbox row is still
there; on restart it picks up where it left off. If APNs is down, the worker
retries with backoff. The API path never blocks on APNs.

### 4.3 The scheduler: `FOR UPDATE SKIP LOCKED`

The "fire reminders at their due time" job is a polling loop on a Postgres
table. The naive query has a problem: if we run two worker replicas (we want
to, for HA), both might pick up the same row.

Postgres solves this elegantly with `SKIP LOCKED`:

```sql
SELECT id FROM reminders
WHERE due_at <= now() AND deleted_at IS NULL
  AND is_completed = false AND pushed_at IS NULL
ORDER BY due_at LIMIT 100
FOR UPDATE SKIP LOCKED;
```

Each worker grabs a batch, locks those rows, and skips anything another worker
has locked. No external job queue, no Redis, no Kafka — just Postgres. For an
MVP this is genuinely sufficient and dramatically simpler.

We poll every 5 seconds. That's the worst-case delay between `due_at` and a
push being sent. The local notification, scheduled in advance, fires precisely
on time, so the user-visible timing is fine; the server push is the backup.

### 4.4 APNs reliability

APNs over HTTP/2 is a finicky integration. The server has three patterns to
keep it healthy:

- **Idempotent pushes via `apns-collapse-id`**: we set it to the reminder ID,
  so even if our retry logic over-delivers, APNs collapses duplicates on the
  device side.
- **Per-device-token circuit breaker**: after 5 consecutive failures to a
  given device, we open the circuit for 60 seconds and stop hammering it.
  Half-open lets one probe through; success closes the circuit.
- **Exponential backoff with jitter**: failed push attempts re-enter the
  scheduled-push table with `next_attempt_at = now() + min(60s · 2^n + jitter,
  1h)`, up to 6 attempts before being marked permanently failed.

### 4.5 High availability

- Two API machines, rolling deploys, health-checked at `/readyz`. A crash
  doesn't drop traffic.
- One worker process for the MVP (worker leadership via a Postgres advisory
  lock if we scale to two; with `SKIP LOCKED` running two workers is safe but
  unnecessary at MVP load).
- Multi-AZ Postgres via Fly Postgres HA (`fly pg create --ha`): synchronous
  replica plus automated failover.
- Graceful shutdown: SIGTERM → stop accepting new connections → drain
  in-flight (30s deadline) → close DB pool → close APNs HTTP/2 channels.
- Stateless app tier: any machine can serve any request; no session affinity.

### 4.6 Observability

- Structured JSON logs via `swift-log`. Every line carries `request_id`,
  `user_id` (when present), and `route`.
- `X-Request-ID` propagated end-to-end; the iOS client generates one per
  request, the server reuses or generates one, and it shows up in every log.
- Prometheus metrics at `/metrics`:
  - `notifications_dispatched_total{result="ok|fail"}`
  - `outbox_lag_seconds` (oldest pending outbox row age)
  - `apns_send_duration_seconds` histogram
  - `http_request_duration_seconds{route}` histogram
- SLO suggestion: `notifications_dispatched_total{result="ok"}` ÷ total ≥
  99.5% over 30 days for the *backup* channel; the local channel is the
  primary correctness path and is verified per-build via UI tests.

## 5. Deployment (Fly.io)

We chose Fly because it gives multi-AZ HA, managed Postgres, and global
deployment with very little YAML. Concretely:

- One Fly app with two `[processes]`: `api` (the HTTP server) and `worker`
  (the scheduler + outbox dispatcher). Same binary, different command.
- `min_machines_running = 2` for `api`, `1` for `worker`.
- Fly Postgres HA cluster, attached to the app via `fly pg attach`.
- Secrets in Fly's secrets store, never on disk:
  `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APPLE_BUNDLE_ID`,
  `JWT_SIGNING_KEY`.
- Single primary region (`iad`) for the MVP. Read replicas in other regions
  are a later step; the architecture supports it (the workers just need
  primary affinity).

## 6. Honest limitations

We surface these so a reader doesn't go away with false confidence.

- **The "real" alarm-clock experience needs Critical Alerts.** The chained
  notification approach is the best we can do without that entitlement, and
  the silent switch will still silence sound. The code path is feature-flagged
  so we can flip it on the day Apple approves the entitlement.
- **`BGAppRefreshTask` is opportunistic.** iOS may decide not to wake us for
  hours. Don't rely on it for correctness; it's a best-effort opportunity to
  drain the sync queue early.
- **APNs is best-effort.** The local notification is the source of truth.
  The server push is a backup that mainly helps after app reinstall, on a
  second device, or when local scheduling fails.
- **Recurring reminders are out of scope for the MVP.** We store
  `recurrence_rule` (RFC 5545 RRULE) but the scheduler treats reminders as
  one-shot. Adding recurrence requires DST/timezone-correct expansion, which
  is its own non-trivial body of work.
- **Single primary region.** The architecture supports read replicas and
  region pinning but the MVP runs only in `iad`.
- **The custom `.caf` file is a placeholder.** It cannot be generated by an
  agent; the user needs to drop in a 28-second `.caf` (instructions in
  `docs/sounds/README.md`). Until then the loud path falls back to the system
  default sound and logs a warning.
- **`idempotency_keys` grows unbounded** without TTL. A daily cleanup query
  (`DELETE WHERE created_at < now() - interval '24 hours'`) is part of the
  worker's housekeeping pass.

## 7. How to read the rest of this repo

- `ios/TaskReminder/TaskReminder/Services/SyncableTaskStore.swift` —
  the offline-first write path.
- `ios/TaskReminder/TaskReminder/Services/NotificationManager.swift` —
  the loud-alarm scheduling.
- `server/Sources/App/Jobs/DueReminderPollerJob.swift` — the
  `FOR UPDATE SKIP LOCKED` poller.
- `server/Sources/App/Services/APNsService.swift` — the push path with
  circuit breaker.
- `server/Sources/App/Controllers/AuthController.swift` — Sign in with
  Apple verification.
- `infra/fly.toml` — the deployment shape.

If you read those six files in order, the entire system makes sense.
