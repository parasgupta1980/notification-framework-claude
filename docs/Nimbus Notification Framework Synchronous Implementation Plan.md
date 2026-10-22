# Nimbus Notification Framework: Synchronous Implementation Plan

*22 October 2026. Draft for review. Platform: Salesforce B2B Commerce on Experience Cloud LWR. Replaces the background-worker processing in the Recommended Design (sections 3 and 5) with synchronous processing, because audiences per notification request are small and Async Apex is to be avoided.*

## 1. Approach

Everything from accept through delivery happens in the caller’s transaction. Slices 1 and 2 stay as they are, apart from the cleanup in section 4. This plan starts at slice 3.

```text
Flow / Apex caller
  └─ NotificationIngress.submit(inputs)          bulk invocable, one transaction
       1. validate, kill switch, find the Active definition by Key
       2. dedupe by EventKey (idempotent; conflict on a different payload)
       3. insert Request (Accepted)
       4. NotificationProcessor.process(requests)
            resolve  → AudienceResolver (by Audience_Resolver_Key__c)
            evaluate → preferences + group policy
            insert Delivery rows (unique DeliveryKey__c absorbs duplicates)
            email    → send in the same call, record the outcome
       5. set Request status: Completed / CompletedWithErrors / Rejected
```

- **Atomicity.** The Request and its Deliveries commit or roll back together, so there is no sweeper and no half-processed request.
- **Request states.** Accepted, then Completed, CompletedWithErrors or Rejected. Expired stays for old requests.
- **Bell delivery states.** Visible, Suppressed or Expired.
- **Email delivery states.** Pending, then Accepted, Suppressed or Failed. `sendEmail` reports success or failure inside the call, so the Unknown state is not needed.
- **Retry.** There is no timed retry. Support replays a Failed email through an admin action.

## 2. Limits budget (to confirm with real numbers)

| Limit (synchronous) | Plan |
| --- | --- |
| 10,000 DML rows | Cap at 1,000 recipients per request (1 Request plus up to 2 rows per recipient) |
| 100 SOQL, 50,000 query rows | Bulk-query definitions, groups, preferences and users once per call, never per request |
| 10 s CPU, 6 MB heap | Check `Limits` before each request. Stop and mark the rest Rejected instead of hitting an uncatchable limit exception |
| 10 `sendEmail` calls | Group messages into as few calls as possible. Verify the per-call recipient cap in G3 |

The cap and the safety margins go in `Notification_Setting__mdt`, so they can change without a deployment. The caller’s own DML counts against the same limits, so the check must look at what is already used.

## 3. Slices

### Slice 3: Ingress and ledger

- `NotificationIngress` invocable. Input: source, business event ID, definition Key, store key, context JSON, Account, and a `failOnError` flag.
- Checks: required fields, source and channel kill switch (`NotificationConfig.isKilled`), exactly one Active definition for the Key, context size cap (32 KB), unknown tokens rejected.
- Dedupe: look up `EventKey__c` in bulk. An identical payload returns the existing request. A different payload returns a conflict result.
- Output: one result per input (request ID, status, error code). With `failOnError`, throw so the source transaction rolls back. Otherwise record a Rejected request with a redacted code.
- Tests: bulk of 200 inputs, duplicates, conflict, kill switch, missing definition.

### Slice 4: Processor with a stub resolver (first end-to-end Bell)

- `AudienceResolver` interface keyed by `Audience_Resolver_Key__c`, with a registry through the `EventRegistry` setting.
- A stub `ExplicitUserResolver` for sandbox use, guarded by a setting so it cannot run in production.
- Evaluate step: until preferences exist, use group defaults and ignore opt-out for Mandatory groups.
- Insert Deliveries with `Database.insert(rows, false)`. Duplicate-key errors count as success (already delivered). Any other error sets CompletedWithErrors.
- Bell rows: Status Visible, `Visible_At__c` now, `Expires_At__c` from the definition’s Expiry Days.
- Tests: audience over the cap is Rejected, replay creates no duplicates, partial failure, limit-guard behavior.

### Slice 5: Preferences (blocked on D11 and D14)

- `Notification_Preference__c` (Contact and Group, Bell and Email choices Enabled, Disabled or Inherit, a version for stale-save conflicts, changed by, time and source), the validator, the service, and the My Profile LWC.
- The processor reads preferences in one bulk query per call.

### Slice 6: Real resolver and entitlements (blocked on G2)

- Entitlement, geography, role and store rules, and the real `NotificationStoreAccess`. Resolvers must page their own queries within the 50,000-row limit.

### Slice 7: Email adapter (after G3)

- Send to the User record with save-as-activity off, rendered per recipient in the Contact’s language with whole-bundle English fallback. Record Accepted or Failed with an error code.
- Replay: an admin action that reprocesses Failed rows by `DeliveryKey__c` and cannot reset an Accepted row.

### Slice 8: Housekeeping without a scheduler

- Purge expired Bell rows in bounded batches inside ingress and inbox calls, plus an admin action to run it on demand. Add storage monitoring, because a scheduled purge is not available.
- Request tombstones are kept per the replay horizon.

### Slice 9: Hardening

- Rewrite T07, T09 and T13 as in the design. T16 becomes poll load only (no worker latency). T17 covers storage growth.
- Add limit tests with maximum audience and two channels, and a test where the caller has already used most of its DML.
- Use real external-user sandbox tests, not only `System.runAs`.

## 4. Changes to existing code (cleanup, after slice 4)

- Remove the lease and retry fields: `Lease_Token__c`, `Lease_Expires_At__c`, `Next_Retry_At__c` and `Attempt_Count__c` on Delivery, and `LastProcessedKey__c` on Request. Update the permission sets.
- Remove or repurpose the `Retry_Email` setting and `NotificationConfig.retryOffsetsMinutes`.
- Update the design document: sections 3 and 5 (states, sweeper, retry) and the estimate.

None of these have been removed yet.

## 5. Decisions needed

1. The recipient cap per request (1,000 proposed) and what happens above it: reject, or truncate with CompletedWithErrors.
2. Failure policy per trigger: roll back the source transaction, or record Rejected and continue.
3. Email retry: manual replay only, or also retry opportunistically on the next ingress call.
4. Purge approach in slice 8.
5. Whether producers other than Flow or Apex (the REST endpoint) are still needed. REST would run the same synchronous path in its own transaction.

## 6. Estimate impact

This should reduce effort in workstream E (ingress, dispatcher, workers), G (state machine) and H (purge jobs), because the sweeper, leases, retries and worker paging disappear. Limit guards and the admin replay add some of it back. The net figure has not been measured, so re-baseline after slice 4.
