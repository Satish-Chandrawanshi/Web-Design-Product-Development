# Custom alarm sound (`alarm_long.caf`)

The loud-alarm code path expects a Core Audio Format file named
`alarm_long.caf` in `ios/TaskReminder/TaskReminder/Resources/Sounds/`. Until
this file exists in the bundle, `NotificationManager` falls back to the system
default sound and logs a warning.

## Constraints (from Apple's `UNNotificationSound` rules)

- Format: `.caf`, `.aiff`, `.wav`. We use `.caf` for best compatibility.
- Sample format: linear PCM, IMA4, MA3, MA5, µLaw, aLaw.
- Maximum duration the system will play: **30 seconds**. The chained-
  notification trick we use schedules three of these ~32 seconds apart, so
  aim for **28 seconds** to give a 4-second gap between rings.
- The file must be inside the app bundle's main resources or in
  `Library/Sounds/`. We bundle ours via the Xcode "Copy Bundle Resources"
  build phase.

## Generating the file (macOS)

Starting from any royalty-free 28-second AIFF or WAV (e.g. exported from
GarageBand or downloaded from a CC0 source):

```sh
# Convert to .caf with the encoding the OS prefers for notification sounds.
afconvert -f caff -d LEI16@44100 -c 1 alarm_long.aiff alarm_long.caf
```

Verify duration:

```sh
afinfo alarm_long.caf | grep duration
```

## Quick placeholder

If you just want the build to ring with *something* while you produce the real
asset, you can copy a system sound:

```sh
cp /System/Library/Sounds/Alarm.caf \
   ios/TaskReminder/TaskReminder/Resources/Sounds/alarm_long.caf
```

The system Alarm.caf is short, so chaining three of them produces three quick
beeps with long gaps. It's adequate for development; replace with a 28-second
asset before shipping.

## Adding to the Xcode project

1. Drag `alarm_long.caf` into the `Resources/Sounds/` group in Xcode.
2. In the file inspector, confirm the file is a member of the `TaskReminder`
   target and appears in **Build Phases → Copy Bundle Resources**.
3. Run on device. The first `loud` reminder should ring with the new sound.
