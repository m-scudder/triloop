# History-aware Coach: provider prerequisites

Verified against official provider documentation on 2026-09-29.

This branch implements only the common provider boundary and Apple Health-backed evidence already available to Athevia. It does **not** add a direct Garmin, WHOOP, or Strava connection and does not expose fake connected states.

## Apple Health

The first coach slice uses Athevia's existing HealthDataProviding and workout reconciliation paths. Records retain their HealthKit UUID and source application label. A record whose source application mentions Garmin, WHOOP, or Strava is represented as an **Apple Health bridge**, not as a direct account connection.

The coach context is bounded to recent summaries and a capped set of recent workout evidence. GPS routes and free-form workout feedback notes are not included.

## Garmin Connect Developer Program

Status: **possible follow-up, subject to program approval and license review**.

Official requirements reviewed:

- Garmin Connect Developer Program is a business/enterprise program and requires an application/approval step.
- APIs use OAuth 2.0.
- Activity API supports REST plus push or ping/pull delivery, developer backfill tooling, and FIT/GPX/TCX activity detail.
- Health API exposes all-day metrics including heart rate, sleep, steps, stress, Pulse Ox, Body Battery, respiration and related summaries.
- Training API can publish structured workouts/training plans for compatible Garmin devices.
- Garmin's current brand guidelines require Garmin attribution when Garmin device-sourced data is used in combined/derived analytics, machine learning or AI outputs.
- Garmin states some commercial metrics/use cases can require license fees or other commercial terms. The applicable partner license must be reviewed before implementation.

Official references:

- https://developer.garmin.com/gc-developer-program/
- https://developer.garmin.com/gc-developer-program/program-faq/
- https://developer.garmin.com/gc-developer-program/activity-api/
- https://developer.garmin.com/gc-developer-program/health-api/
- https://developer.garmin.com/brand-guidelines/api-brand-guidelines/

Follow-up implementation must verify the approved application's actual scopes/data fields, webhook or push semantics, backfill limits, revocation/deletion obligations, retention rights, AI-processing rights and any rate limits exposed in the partner portal before code is merged.

## WHOOP Developer Platform

Status: **do not implement for the coach until current-at-implementation terms explicitly permit the intended AI use**.

Official API capabilities reviewed:

- OAuth 2.0 with user-granted scopes including read:workout, read:sleep, read:recovery, read:cycles, profile and body measurement scopes.
- Collection APIs are paginated; current workout collection documentation caps a page at 25 records.
- Default published rate limits are 100 requests/minute and 10,000 requests/day.
- Webhooks may be duplicated or missed, so integrations should deduplicate webhook events and periodically reconcile against the API.
- DELETE /v2/user/access revokes the user's OAuth access; webhook delivery stops for that user after revocation.
- Apps are submitted for approval before launch.

Important terms issue:

WHOOP currently publishes new API Terms with an **effective date of 2026-10-06**. Those terms prohibit using WHOOP APIs or WHOOP Data to create, develop, test, train, fine-tune, improve, or operate an LLM/ML/AI application or system, and restrict permanent copies/caching. Since this date is one week after this review, a direct WHOOP-backed Athevia conversational coach must not be implemented on a later branch without re-checking the terms then and obtaining written authorization if required.

Official references:

- https://developer.whoop.com/docs/developing/overview/
- https://developer.whoop.com/docs/developing/oauth/
- https://developer.whoop.com/api/
- https://developer.whoop.com/docs/developing/rate-limiting/
- https://developer.whoop.com/docs/developing/pagination/
- https://developer.whoop.com/docs/developing/webhooks/
- https://developer.whoop.com/api-terms-of-use/

## Strava API

Status: **blocked for this AI coach through the ordinary Strava API under the current policy**.

As of 2026-09-29, the Strava API Agreement and API Policy are effective 2026-06-01. The current policy:

- Requires authentication and legal consent with disclosures covering data collection, withdrawal and deletion.
- Starts new API applications in single-player mode until review.
- Publishes default limits of 200 requests/15 minutes and 2,000/day overall, with a separate non-upload limit of 100/15 minutes and 1,000/day.
- Encourages webhooks rather than polling; webhook events include authorization revocation and activity create/update/delete.
- Prohibits use of Strava API Materials or Strava Data in connection with the development, training, evaluation **or operation** of an AI Application, including context-window ingestion/RAG.
- Prohibits transfer/disclosure to AI Application providers or model developers even with end-user consent.
- Limits ordinary Strava Data caching to seven days, requires prompt deletion/reflection of revocation/deletion, and imposes additional deletion obligations.
- Identifies Strava MCP as the policy's authorized first-party agent-mediated path; that is a separate product/authorization question and is not implemented here.

Because the coach's purpose is to use athlete evidence to operate a conversational AI interface, the ordinary Strava API must not be wired into the coach while this policy applies.

Official references:

- https://developers.strava.com/docs/getting-started/
- https://developers.strava.com/docs/rate-limits/
- https://developers.strava.com/docs/webhooks/
- https://www.strava.com/legal/api
- https://www.strava.com/legal/api_policy

## Required follow-up branch discipline

Each direct provider integration must be a separate feature branch created from the then-current main. It must preserve provenance, use stable provider record IDs for idempotency, reconcile webhook/backfill gaps, implement disconnect/revocation/deletion behavior, and pass the same conservative cross-source deduplication tests before becoming a source for athlete context.
