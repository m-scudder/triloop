# Athevia product analytics

This branch adds owner-controlled product analytics using PostHog's public `/batch/` API.
There is no PostHog SDK dependency, automatic UI/text capture, screen recording,
remote configuration, advertising identifier or LLM access. Explicit identity linking associates
guest activity with an opaque account ID after sign-in.
The Xcode project uses synchronized source folders, so new app/test files are
included without manually editing project.pbxproj.

## Connect the projects

1. Sign up at https://posthog.com and create an Athevia organization.
2. Create `Athevia Production` and choose US or EU hosting. Select Product Analytics.
3. Copy the **project token** (`phc_...`) and API host from project settings/onboarding.
   Never use a personal (`phx_...`) or secret API key in the app.
4. Athevia currently uses one Production project. Debug shares it explicitly; a separate development project is optional.
5. Set these strings in `Athevia/Info.plist`:

| Key | Value |
| --- | --- |
| PostHogProductionToken | Production project token |
| PostHogProductionHost | `https://us.i.posthog.com` or `https://eu.i.posthog.com` |
| PostHogDevelopmentToken | Optional separate development project token; currently empty |
| PostHogDevelopmentHost | Optional development project host; currently empty |
| PostHogDebugUsesProductionProject | `true` enables manual Debug testing in the production project |

Empty or invalid configuration disables collection. There is no analytics permission popup or user-facing analytics switch.
The owner-confirmed US production project is configured with its ingestion token
and `https://us.i.posthog.com`. `PostHogDebugUsesProductionProject=true` explicitly
allows Debug builds to send to this same project, with `environment=development`.
App Store events use `environment=production`. Always filter production dashboards
by **environment equals production**, so manual testing does not inflate reports.
Project ingestion tokens are public client configuration; they do not grant dashboard read access.

Debug always selects the development label. The shared-project override requires a
Debug binary and cannot enable TestFlight or ad-hoc Release collection. A sandbox
receipt selects TestFlight; its separate development configuration is currently empty,
so TestFlight stays disabled. Release with an App Store receipt named `receipt`
selects production; missing/unrecognized receipts select development without the
Debug override. To use a separate development project later, supply its token/host
and set `PostHogDebugUsesProductionProject=false`.

Xcode previews, unit tests, existing UI-test launch arguments and `--disable-analytics`
suppress the shared collector. Manual Xcode Run is supported.
Configured supported builds begin product analytics automatically after account resolution.

## Product analytics behavior and data

Analytics is not exposed as a user preference. There is no first-launch analytics prompt
and no Settings entry or switch. When the bundled PostHog configuration is valid,
collection starts automatically after authentication resolves; tests, previews and the
existing analytics-disable launch argument remain suppressed.

The typed event schema accepts fixed enum values only. It never accepts a workout,
profile, date selection, health reading, route, note, chat message or error description. A separate identity method accepts only the
stable authentication user ID and derives a SHA-256 account identifier; raw account IDs
never enter event properties or logs. Request/result events describe software actions, not athletic
performance. Import success means the import operation returned without throwing;
it does **not** mean there were any matching workouts or that Health read access was granted.

Events contain a random installation UUID, random session UUID, event UUID, event
timestamp, app version/build, environment and schema version. Screens add a fixed
screen name; onboarding adds a fixed step name. Sessions rotate after 30 minutes
without an event. Guest events use `$process_person_profile=false`; signed-in events
and `$identify` use `true` and `$is_identified=true`. GeoIP enrichment is disabled
(`$geoip_disable=true`). PostHog necessarily receives
the network request's IP at the transport layer; this is not a promise of anonymity.
On sign-in, `$identify` carries the old installation UUID as `$anon_distinct_id` and
the hashed account ID as `distinct_id`. Subsequent events use that account ID. PostHog
can therefore associate earlier guest events and signed-in events with one person.
The hash is pseudonymous, not anonymous, and is not a secret. It is SHA-256 of
`athevia.analytics.v1:<environment>:<userID>` prefixed with `account_`; UUID user IDs
are lowercased first. Use `ProductAnalytics.accountIdentifier` for exact lookup.
Development and production use separate account namespaces in the shared project.
No name, email, health records or account profile properties are sent.

The shared collector pauses capture/flush until authentication resolves. A cached
account's queue cannot be sent as the next account. Refresh/checking/failure states
are not treated as logout; explicit local continuation resolves to the current account
or guest. Repeated identity calls in a process do not duplicate the merge. Each new
launch reasserts the same merge, recovering from cache eviction or an interrupted write.

Sign-out, account replacement and local erasure rotate the installation identity and
clear unsent events before the next account or guest session continues. Cancellation
cannot retract requests already received by PostHog. Configure server-side retention
in PostHog and document the retention/deletion process in the published privacy policy
before release.

A normal delete-and-reinstall without login generally produces a new installation ID:
there is no reliable way to know that it is the same person. Offloading the app or
restoring app data from a backup can preserve preferences and the identifier. No
Keychain analytics ID, device fingerprint, IDFA or IDFV is used. Signing into the same
account after reinstall can associate the new installation's activity with that account;
a previous never-identified installation cannot be recovered this way.

## Reliability

- At most 200 pending records; usage events older than seven days are discarded.
  A pending identity merge is protected from overflow/expiry during the process;
  after restart an expired/missing merge is re-created. iOS can evict the cache sooner.
- Cache files excluded from device backup and protected until first device unlock.
- Flush at 20 events, every 30 seconds while active, and best-effort on backgrounding.
- Batches up to 50 records. Stable UUIDs across retries support server deduplication.
- Transport failures, 408, 429 and 5xx use exponential backoff; numeric Retry-After
  is respected up to one day. Other HTTP failures drop that batch.
- Generation checks stop an old cancelled completion touching a newly rotated queue.
- Analytics is best-effort: suspension, cache eviction and queue overflow can lose
  events. It never blocks a workout, changes a plan or displays network failures.

## Event catalog

| Event | Trigger / properties |
| --- | --- |
| `$identify` | Account linking; `$anon_distinct_id` is the installation UUID |
| `app_opened` | Foreground transition after analytics/account resolution is active |
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

Create these inside the **production** project after real events arrive. Apply
`environment = production` to every production insight/dashboard:

1. Usage: unique persons for `app_opened`, daily/weekly. `$screen` breakdown by
   `$screen_name`; compare app versions. Exclude development/testflight if importing data.
2. Onboarding funnel: welcome → starting_point → schedule → preview → completed,
   filtering each step's `step` property; use a seven-day conversion window.
3. Retention: first `onboarding_completed` → returning `app_opened`, day 1/day 7.
   Existing users won't have onboarding completion; analyze them separately.
4. Feature adoption: unique users for explanations, imports, plan updates and goal
   setup; show requested/succeeded/failed counts separately.

These dashboards describe collected product-analytics users only. No custom historical taps can be
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

Manual check in the existing Production project (filter `environment = development`):

Pull `feat/product-analytics`, select the Athevia scheme and **Debug** Run configuration,
then run on your iPhone. Use normal Run, not the unit/UI-test runner. In PostHog,
open Activity → Live events and filter for `environment = development`.

1. Fresh launch: confirm there is no analytics prompt and no Usage Analytics item in Settings.
2. Open Home/Plan/Progress and tap Why. Wait 30 seconds or background the app. Verify names/properties in PostHog Activity/Live events.
3. Confirm repeated view redraws do not add duplicate screen views; navigation back and switching tabs should count as new views.
4. Go offline, navigate, reconnect: events retry with original timestamps/UUIDs.
5. Sign out/erase local data: unsent events are cleared, the installation identity rotates, and analytics continues automatically.
6. TestFlight: no events should be sent with the current empty development configuration.
7. Guest → sign in: first capture guest events, then sign in and use another screen.
   Confirm `$identify` includes the earlier guest distinct ID as `$anon_distinct_id`,
   and the person timeline contains both guest and account events after processing.
8. Restart offline with queued account events, then sign in as another account: old
   queued events must be cleared. Same-account restart must retain the pending merge UUID.
9. Delete/reinstall without restoring data: verify a fresh guest ID.
   Sign in with the same account on another device: verify the same account ID.
10. Archive: verify privacy manifest is bundled, and run iPhone/Watch build checks.

PrivacyInfo.xcprivacy declares this analytics addition (product interaction and a
device-specific identifier and user identifier, marked linked, analytics purpose, no
tracking) and app-owned UserDefaults access. This is not an audit of all existing
account/backup/health data flows. Review the complete app's privacy report and update
App Store Connect disclosures and published privacy policy before release.

This workspace has no Xcode or Swift compiler. Swift syntax parsing, plist parsing,
diff checks and source review can be performed here; the tests/build and actual
PostHog ingestion must be verified in Xcode and the shared project using the development filter.

References:
- https://posthog.com/docs/api/capture
- https://posthog.com/docs/data/anonymous-vs-identified-events
- https://developer.apple.com/app-store/user-privacy-and-data-use/

Identity wire-format reference:
- https://github.com/PostHog/sdk-specs/blob/main/openspec/specs/identify/spec.md
