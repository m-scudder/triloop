# Switchable Gaming appearance

Branch: `feat/app-gaming-theme`, based on main commit `de84dfeb14cf5e4dd9eaff6376f22d02fd33f3bc`.

## Try it

Fetch the branch, open `Athevia.xcodeproj`, select the Athevia scheme and run on an iPhone or simulator. Open **Settings → Appearance → Gaming theme**. Turn it off to restore Classic. The choice survives relaunch. Classic is the default for existing and new installations.

Gaming uses deep purple surfaces, lime actions, cyan highlights, gold achievements, outlined cards and rounded type. Navigation, screen order, controls, workout prescriptions and training decisions remain the existing app's. This is an appearance mode; it does not introduce points or game mechanics.

## Change the colours

Edit `GamingPalette.hex(_:)` in `AtheviaTheme/AtheviaTheme.swift`. This shared source belongs to the iPhone, Watch and Live Activity targets. Change roles such as `canvas`, `surface`, `hero`, `accent`, `onAccent` and sport colours there. No per-screen replacement is required for Gaming tokens. Classic retains its original styles at the call sites. Data charts retain existing metric colour semantics, and Apple-owned permission, authentication and sharing interfaces retain system styling.

The text/accent contrast tests should remain green after palette changes.

## Behaviour

- `@AppStorage` persists `athevia.gamingThemeEnabled.v1` on the device. The root supplies a SwiftUI environment value without replacing the navigation hierarchy or adding a theme-dependent view identity.
- Screen, list, card, chip and button styles resolve from that environment. Custom colours, gradients and materials retain their Classic branch.
- Watch receives the preference in the existing workout-list application context. An offline Watch changes when connectivity delivers the next payload. An optional field keeps schema-v2 payloads compatible with older app versions.
- Active Live Activities receive a cosmetic update. Theme and workout updates share an ordered queue, preserving step/timer state. Their optional theme field supports activities created before this change.
- No model migration, planning rule, workout step, account operation or HealthKit operation is introduced by the switch.

## Validation

Performed in the implementation environment: diff whitespace checks; Swift syntax-tree comparison against the main snapshot (no new parser errors); shared target membership review; text/accent contrast calculations. These are source checks, not a Swift typecheck or simulator run.

Xcode and Apple SDKs are unavailable in that environment. **Builds, unit tests, UI tests and on-device visual verification have not been run.** Before merging, build all three targets in Xcode and run:

- `AtheviaThemeTests`: saved preference, Watch payload compatibility, Live Activity state compatibility and palette text contrast.
- `AtheviaUITests.testGamingThemeSwitchPersistsAndKeepsNavigation`: toggle, main tabs, relaunch, restoration, screenshot attachments.
- Existing workout execution and Watch transfer tests.

Manually review onboarding, Home, Plan, Progress, Settings and their details/sheets in both modes; Classic in light and dark system appearance; large text and VoiceOver; feedback selected chips; a running/paused workout; locked-screen Live Activity; and a paired Watch reconnecting after being offline. Confirm elapsed time, drafts, selections and navigation are preserved. OS-owned presentation surfaces are outside the custom theme.
