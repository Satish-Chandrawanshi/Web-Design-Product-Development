# Task Reminder iOS App

Task Reminder is a SwiftUI-based iOS application that helps people plan their day by organising daily tasks and scheduling timely reminders. The app focuses on a lightweight experience: it is quick to add a new reminder, easy to review upcoming work, and simple to mark items as complete once they are done.

## Features

- **Daily agenda at a glance** – View upcoming and completed tasks in a grouped list with rich context such as due time, notes, and reminder status.
- **Quick capture** – Create new reminders with a title, due date, optional notes, and control over whether a notification should be scheduled.
- **Local notifications** – The app requests notification permission on launch and schedules/cancels local alerts as tasks are created, updated, or marked complete.
- **Smart sorting** – Choose between multiple sort orders (due date, creation date, alphabetical, completion) to organise the task list in a way that best fits your workflow.
- **Persistent storage** – Tasks are stored locally as JSON so that reminders survive app restarts.
- **Accessibility-minded design** – Buttons, labels, and colour choices are built to support VoiceOver and Dynamic Type users.

## Architecture

The application is organised into a few simple layers:

- `Task` – The core data model representing a reminder, including title, notes, due date, completion state, and notification preference.
- `TaskStore` – A lightweight persistence service that saves and restores tasks from the user's document directory using `Codable`.
- `NotificationManager` – An `actor` that coordinates `UNUserNotificationCenter` authorisation requests and schedules/cancels reminder notifications.
- `TaskViewModel` – An `ObservableObject` responsible for orchestrating mutations on the task list, applying sort/filter settings, and coordinating persistence + notifications.
- SwiftUI `Views` – Composable screens for listing tasks, creating a new reminder, editing existing ones, and showing an empty state.

The folder structure under [`TaskReminder/TaskReminder`](TaskReminder/TaskReminder) mirrors this architecture with `Models`, `ViewModels`, `Services`, `Views`, and `Resources` groupings. This layout matches what you would see when opening the project in Xcode, making it simple to navigate.

## Getting Started

1. Open **Xcode 14** (or newer) on macOS.
2. Choose **File → Open** and select the [`TaskReminder`](TaskReminder) folder.
3. Set the run destination to an iOS 16+ simulator or connected device.
4. Build and run the project. The first launch will request notification permission; grant access so reminders can be scheduled.

> **Tip:** If you prefer working from a fresh template, you can create a new SwiftUI App project in Xcode and replace the generated files with the sources in this repository. Ensure the resource files (asset catalog and `Info.plist`) are copied into the target.

## Requirements

- iOS 16.0 or later
- Xcode 14 or later

## Next Steps

Some ideas to continue evolving the product:

- Sync reminders with Calendar or Reminders via CloudKit.
- Add widgets or Live Activities to surface upcoming tasks.
- Support subtasks, priorities, or recurring reminders.
- Provide data export/import for backups.

## License

This project is released under the [MIT License](LICENSE).
