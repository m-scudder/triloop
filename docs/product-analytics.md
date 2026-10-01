# Athevia product analytics

This branch adds opt-in product analytics using PostHog's public `/batch/` API.
There is no PostHog SDK dependency, automatic UI/text capture, screen recording,
remote configuration, advertising identifier, account identification or LLM access.
The Xcode project uses synchronized source folders, so new app/test files are
included without manually editing project.pbxproj.

## Connect the projects

1. Sign up at https://posthog.com and create an Athevia organization.
2. Create `Athevia Production` and choose US or EU hosting. Select Product Analytics.
3. Copy the **project token** (`phc_...`) and API host from project settings/onboarding.
   Never use a personal (`phx_...`) or secret API key in the app.
4. Create a separate `Athevia Development` project for Debug and TestFlight.
5. Set these strings in `Athevia/Info.plist`:

| Key | Value |
| --- | --- |
| PostHogProductionToken | Production project token |
| PostHogProductionHost | `https://us.i.posthog.com` or `https://eu.i.posthog.com` |
| PostHogDevelopmentToken | Different development project token |
| PostHogDevelopmentHost | Development project's matching ingestion host |

Empty or invalid configuration disables collection and the initial consent sheet.
No project token is configured yet: the supplied token's region and intended
environment still need confirmation. Do not send test events to an assumed region.
Project ingestion tokens are public client configuration and can be committed once
the owner confirms their environment. They do not grant dashboard read access.

Debug always selects development. A sandbox receipt selects TestFlight, which uses
the development project. A release build with an App Store receipt named `receipt`
selects production; a missing/unrecognized receipt selects development. The code
refuses to use the same token for production and development. Xcode previews,
unit tests, existing UI-test launch arguments and `--disable-analytics` suppress
the shared collector regardless of consent.

## User choice and data

On entering the local app, configured builds offer a one-time optional choice before
onboarding. "Not now" or dismissing the sheet declines; there is no repeated prompt.
Settings → Usage Analytics lets users change the choice. No event or identity is
created before opt-in. The network transport is idle until a consented event is sent.

The typed event schema accepts fixed enum values only. It never accepts a workout,
profile, date selection, health reading, route, note, chat message, account identifier
or error description. Request/result events describe software actions, not athletic
performance. Import success means the import operation returned without throwing;
it does **not** mean there were any matching workouts or that Health read access was granted.

Events contain a random installation UUID, random session UUID, event UUID, event
timestamp, app version/build, environment and schema version. Screens add a fixed
screen name; onboarding adds a fixed step name. Sessions rotate after 30 minutes
without an event. No person profile is created (`$process_person_profile=false`),
and GeoIP enrichment is disabled (`$geoip_disable=true`). PostHog necessarily receives
the network request's IP at the transport layer; this is not a promise of anonymity.
No account ID/email is sent or joined to the installation UUID. Counts therefore
describe installations/consented users, not deduplicated people across devices.

Switching analytics off cancels pending network tasks, clears the local queue and
installation ID, and stops retries. Sign-out, account replacement and local erasure
also reset the choice so the next user is asked separately. Cancellation cannot
retract requests already received by PostHog, and disabling collection does not
delete previously ingested events. Configure server-side retention in PostHog and
document the retention/deletion process in the published privacy policy before release.

## Reliability

- At most 200 pending records; records older than seven days are discarded on
  restore, capture and flush. iOS can evict these cache files sooner.
- Cache files excluded from device backup and protected until first device unlock.
- Flush at 20 events, every 30 seconds while active, and best-effort on backgrounding.
- Batches up to 50 records. Stable UUIDs across retries support server deduplication.
- Transport failures, 408, 429 and 5xx use exponential backoff; numeric Retry-After
  is respected up to one day. Other HTTP failures drop that batch.
- Consent generation checks stop an old cancelled completion touching a new queue.
- Analytics is best-effort: suspension, cache eviction and queue overflow can lose
  events. It never blocks a workout, changes a plan or displays network failures.

## Event catalog

| Event | Trigger / properties |
| --- | --- |
| `app_opened` | Foreground transition, or consent granted while foreground |
| `$screen` | Screen appears; `$screen_name` from list below |
| `onboarding_step_viewed` | `step`: welcome, starting_point, schedule, preview |
| `onboarding_completed` | Onboarding plan successfully persisted |
| `onboarding_failed` | Onboarding plan save failed |
| `why_tapped` / `info_tapped` | Explicit explanation button interaction; no title/content |
| `calendar_opened` | Plan calendar button |
| `import_workouts_requested/succeeded/failed` | Manual imports in Settings and workout details |
| `move_workout_requested/succeeded/failed` | Confirmed move attempt and result |
| `skip_workout_requested/succeeded/failed` | Confirmed skip attempt and result |
| `change_availability_requested/succeeded/failed` | Mark-unavailable attempt and result |
| `update_plan_requested/succeeded/failed` | Profile reassessment or Home reshape and result |
| `create_next_week_requested/succeeded/failed` | Save next-week preview and result |
| `send_to_watch_requested/succeeded/failed` | Explicit Watch send and result |
| `send_to_watch_cancelled` | Watch state changed during the request; no new schedule attempted |
| `start_workout_requested/succeeded/failed` | iPhone player attempts to start the engine and result |

Screen names: `home`, `plan`, `progress`, `settings`, `training_profile`,
`workout_history`, `workout_detail`, `next_week_preview`, `goal_setup`, `explanation`.
Goal setup includes general-fitness goals; do not interpret it as event-specific demand.
Plan's inline workout content is counted as Plan, not a separate detail page view.
Screen modifiers suppress repeated onAppear calls during the same visible lifetime.
Opening an explanation sheet or returning to a screen can produce a new view.
Do not infer dwell time from these events: explicit foreground screen-duration
measurement is not included. Background auto-imports are deliberately not measured.
Coach, paywall and Watch-side usage instrumentation are not part of this branch.

## Initial dashboards

Create these inside the **production** project after real events arrive:

1. Usage: unique distinct IDs for `app_opened`, daily/weekly. `$screen` breakdown by
   `$screen_name`; compare app versions. Exclude development/testflight if importing data.
2. Onboarding funnel: welcome → starting_point → schedule → preview → completed,
   filtering each step's `step` property; use a seven-day conversion window.
3. Retention: first `onboarding_completed` → returning `app_opened`, day 1/day 7.
   Existing users won't have onboarding completion; analyze them separately.
4. Feature adoption: unique users for explanations, imports, plan updates and goal
   setup; show requested/succeeded/failed counts separately.

These dashboards describe opted-in users only. No custom historical taps can be
recovered. Event usage does not establish willingness to buy Pro. Dashboard creation
requires dashboard access and is not accomplished by adding an ingestion token.

## Validation and release

Focused Swift Testing suite: `AtheviaTests/ProductAnalyticsTests.swift`.
Use Xcode Product → Test for this suite, or select an available simulator/device:

```sh
xcodebuild test -project Athevia.xcodeproj -scheme Athevia \
  -destination 'platform=iOS Simulator,name=YOUR_AVAILABLE_IPHONE' \
  -only-testing:AtheviaTests/ProductAnalyticsTests
```

Manual check with the development project:

1. Fresh launch: reject analytics; navigate and import. PostHog receives no events.
2. Enable in Settings, open Home/Plan/Progress and tap Why. Wait 30 seconds or
   background the app. Verify names/properties in PostHog Activity/Live events.
3. Confirm repeated view redraws do not add duplicate screen views; navigation back
   and switching tabs should count as new views. Check consent-sheet dismissal on iPhone.
4. Go offline, navigate, disable analytics, reconnect: pending events must not arrive.
5. Repeat offline, leave analytics on, reconnect: events retry with original timestamps/UUIDs.
6. Sign out/erase local data: new consent choice and new random identity on next opt-in.
7. TestFlight: events must land only in Development with `environment=testflight`.
8. Archive: verify privacy manifest is bundled, and run iPhone/Watch build checks.

PrivacyInfo.xcprivacy declares this analytics addition (product interaction and a
device-specific identifier, conservatively marked linked, analytics purpose, no
tracking) and app-owned UserDefaults access. This is not an audit of all existing
account/backup/health data flows. Review the complete app's privacy report and update
App Store Connect disclosures and published privacy policy before release.

This workspace has no Xcode or Swift compiler. Swift syntax parsing, plist parsing,
diff checks and source review can be performed here; the tests/build and actual
PostHog ingestion must be verified in Xcode and the development project.

References:
- https://posthog.com/docs/api/capture
- https://posthog.com/docs/data/anonymous-vs-identified-events
- https://developer.apple.com/app-store/user-privacy-and-data-use/
