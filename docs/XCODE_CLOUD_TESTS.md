# Xcode Cloud: tests after merging to main

## Repository setup

- Shared scheme: `Athevia CI`.
- Test plan: `AtheviaCI.xctestplan`.
- Includes all tests in `AtheviaTests` and `AtheviaUITests`; no test exclusions.
- Debug configuration, coverage disabled, test targets not marked parallelizable.
- Uses existing test fixtures. No new backend credentials or paid test services.
- This is CI setup for existing coverage, not implementation of the entire blocker test plan.
- Existing app and watch schemes are unchanged.

## Cloud setup status (2026-09-22)

A workflow named `Athevia - Main Tests` has been saved in Xcode Cloud, **inactive**:
- Exact `main` Branch Changes condition; no PR, schedule or tag condition.
- One Test action, Required to Pass; no archive or post-actions.
- One iPhone 16 destination, iOS runtime from selected Xcode.
- Xcode 26.5 (17F42), macOS Tahoe 26.2 (25C56), caching enabled.
- Auto-cancel off so closely spaced merges are not silently superseded.
- Temporary scheme: `Athevia`. Cloud's picker does not yet list `Athevia CI`, which is on this PR branch.
- Existing Test Flight Automation Workflow was inspected and left unchanged; it has only an Archive action.

After merging PR #25, edit the saved workflow to select `Athevia CI` (default plan `AtheviaCI`), enforce PR-only updates to main, then activate. No test or manual build was triggered during setup.

Workflow: https://appstoreconnect.apple.com/teams/06e39095-081d-41a1-a0a6-d2720b3fd929/xcode-cloud/products/B1FF0105-F556-4143-91B6-D77369A36C35/workflows/b9eaafb0-3d6c-41e5-b269-473054aeea32

## Workflow settings reference

In Xcode Cloud's workflow editor in Xcode or App Store Connect:

1. Create a workflow named `Athevia - Main Tests`.
2. Select the shared `Athevia CI` scheme.
3. Use the Xcode/macOS version of the successful app build initially; select a compatible iOS simulator runtime (the app requires iOS 18 or later).
4. Add only the Branch Changes start condition, with the exact custom branch `main`. Remove Pull Request Changes, schedules, tag conditions, and other branch patterns.
5. Leave file filtering unrestricted so every main merge is eligible.
6. Turn Auto-cancel Builds off if every merge must receive a complete test run, including closely spaced merges.
7. Add one Test action, select `AtheviaCI`, and choose one available iPhone simulator/OS combination. Do not choose an all-device matrix.
8. Do not add Archive, distribution or TestFlight post-actions to this test workflow.
9. Save without starting a manual run. The next eligible main update should trigger it.
10. Inspect any other workflows for existing Test actions/start conditions to prevent tests running on PR updates or schedules. Do not disable the existing release/archive workflow inadvertently.

Workflow configuration is stored in Xcode Cloud, not activated by this test-plan JSON.

## Strict merge-only requirement

Apple's Branch Changes condition responds to updates, including direct pushes; it is not a merged-PR webhook.

Before enabling automatic execution, enforce PR-only updates to `main` through a GitHub branch rule/ruleset:
- Require a pull request before merging.
- Prevent direct pushes, including bypass paths applicable to the owner/admin.
- Do not require this post-merge test check before merging: it runs only after the merge.
- Choose review requirements appropriate to the project; this setup does not require adding a second reviewer.

At inspection time on 2026-09-22, GitHub reported main as unprotected. Branch protection has not been changed by this PR. If the account/repository cannot enforce PR-only updates, Branch Changes alone does not meet strict merge-only semantics. Leave the workflow inactive until that is resolved; an authenticated merged-PR event integration would be a separate alternative.

## First-run acceptance

After this PR is merged and the Cloud workflow is activated, use the next normal PR merge as the first run:
- Verify no test run is started for opening or updating that PR.
- Verify the run's commit equals the resulting main commit.
- Verify both test bundles execute and the result contains more than zero tests.
- Inspect failures in Xcode Cloud's test report; retain logs and UI screenshots.
- Record compute usage and elapsed time before expanding destinations.
- Do not hide failures by excluding tests or enabling repeat-until-pass retries.

No iOS build or tests were executed in the Linux editing environment. XML/JSON and target references were statically checked; the first cloud run must validate compilation and runtime behaviour.

## Scope limits

The iOS test target includes shared watch execution/reconciliation tests. This is not a physical Apple Watch run, Bluetooth integration test, or a watch UI suite. Audio output, pool use, real background interruptions, GPS and battery still need device testing.

Post-merge tests detect regressions already on main; they do not prevent that merge and do not automatically gate a separate TestFlight archive workflow.

## References

- https://developer.apple.com/documentation/xcode/configuring-start-conditions
- https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference
