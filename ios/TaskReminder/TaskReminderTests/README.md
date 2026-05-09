# Adding the Tests Target in Xcode

The `TaskReminderTests/` files are not yet wired into a target in
`TaskReminder.xcodeproj` because `project.pbxproj` was generated before this
directory existed. To enable them:

1. Open `ios/TaskReminder/TaskReminder.xcodeproj` in Xcode.
2. **File → New → Target → Unit Testing Bundle**.
3. Name it `TaskReminderTests`, target the existing `TaskReminder` app.
4. In the Project navigator, drag the `.swift` files from this directory into
   the new target's group; confirm "Add to target: TaskReminderTests" is
   checked.
5. Run **⌘U** (Test). All three tests should pass on a simulator.

The test files are named to match the convention used in the Xcode default
template (`<TypeUnderTest>Tests.swift`).
