# Manual end-to-end test

A 10-minute script to verify the dual-channel delivery path on a real device.
Run after every significant backend or notification change.

## Prerequisites

- A real iOS device (the simulator does not deliver remote pushes the way a
  real device does).
- TestFlight or development-signed build of `TaskReminder` on the device.
- Backend deployed to Fly.io (or `fly.toml` adjusted to point at your dev
  instance).
- An APNs key registered in Apple Developer; the matching `APNS_*` secrets
  configured on the Fly app.

## 1. Sign in

1. Launch the app fresh (delete-and-reinstall to start clean).
2. Tap **Sign in with Apple**.
3. Confirm in `fly logs` that `POST /auth/apple` returned 200 and a `User`
   row was inserted.
4. The reminder list appears empty (correct — fresh account).

## 2. Standard reminder fires on time

1. Create a reminder titled "E2E standard", due 60 seconds from now,
   `reminder_type = standard`.
2. Lock the device immediately.
3. Confirm the notification rings within ±5 seconds of the due time.
4. Unlock, swipe the notification away.
5. Confirm in `fly logs` that the server *also* dispatched a push (look for
   `notifications_dispatched_total` incrementing). The client should have
   suppressed the duplicate via the `dedupeKey` mechanism.

## 3. Loud reminder rings ~90 seconds

1. Create a reminder titled "E2E loud", due 60 seconds from now,
   `reminder_type = loud`.
2. Lock the device.
3. Confirm the alarm rings, pauses ~4 seconds, rings again, pauses, rings
   once more — three chained notifications, ~90 seconds total.
4. Open Notification Center; confirm the three notifications are grouped
   under the same thread.

## 4. Force-quit fallback

1. Create a reminder titled "E2E quit", due 90 seconds from now.
2. Force-quit the app from the app switcher.
3. Wait until past the due time.
4. The app is killed, so the *local* notification was already scheduled
   into the OS — it should still fire. Confirm.
5. Re-open the app; the server's APNs backup push should also have arrived
   while the app was killed (visible in Notification Center if it landed
   before the local one was tapped).

## 5. Offline edits sync

1. Enable Airplane Mode.
2. Create three reminders. Edit one. Delete one.
3. Disable Airplane Mode.
4. Within 10 seconds, confirm `fly logs` shows `POST /reminders/batch` with
   the queued ops; confirm the reminders appear with the same content on a
   second signed-in device (if you have one).

## 6. Reinstall recovery

1. Delete the app from the device.
2. Reinstall and sign in with the same Apple ID.
3. Confirm the bootstrap pull (`GET /reminders?since=`) restores the full
   reminder list, including the upcoming alarm-typed ones, and that local
   notifications are re-scheduled for any reminders still in the future.

## 7. Health endpoints

```sh
curl https://<your-app>.fly.dev/healthz   # 200
curl https://<your-app>.fly.dev/readyz    # 200 once DB is reachable
curl https://<your-app>.fly.dev/metrics   # Prometheus exposition
```

`outbox_lag_seconds` should hover near 0 in steady state. A sustained climb
indicates the worker is stuck — check `fly logs --process worker`.

## 8. Cleanup

Delete the test reminders, sign out, optionally revoke the Apple Sign-in
session under iOS Settings → Apple ID → Password & Security → Apps Using
Apple ID.
