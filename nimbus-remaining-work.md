# Nimbus Notification Framework: Remaining Work

Platform: Salesforce B2B Commerce on Experience Cloud LWR.
Sources: the Recommended Design and Build Estimate (17 Oct 2026), the slice 2 README and source, and the slice 2 test failures fixed on 19 Oct 2026.

Items marked **(suggested)** are my sequencing proposals, not decisions from the design doc.

---

## 1. Where things stand

| Slice | Content | Status |
|---|---|---|
| 1 | Bell inbox: 5 core objects, `NotificationInboxController`, `NotificationInboxSelector`, `NotificationRenderer`, `NotificationTargetValidator`, 3 LWCs, 4 permission sets, labels | Passed deployment validation |
| 2 | Integrity and configuration: `NotificationKeys`, 4 triggers and handlers, definition lifecycle, `Notification_Setting__mdt` + `NotificationConfig`, admin app and tabs, new Group and Definition fields | Built. **Not yet deployment-validated.** `fix1` zip addresses the 6 failing `NotificationDefinitionHandlerTest` tests |

### Immediate to-do before starting slice 3
- [ ] **Versioning removed (Definition Version/VersionKey, Group Policy Version, Delivery Evaluated Policy Version).** Deploy the source, then run `manifest/destructiveChanges.xml` if the org already has those fields (steps are in the file). Group field history tracking is now on for the policy fields. Delete the `removed-versioning-fields/` folder once deployed.
- [ ] Deploy `nimbus-notifications-slice2-fix1.zip` to the sandbox.
- [ ] Re-run `NotificationDefinitionHandlerTest`, then the full slice 2 set (`NotificationKeysTest`, `NotificationConfigTest`, `NotificationDefinitionHandlerTest`) and the slice 1 `NotificationInboxControllerTest`.
- [ ] Decide on the Config_Editor change in fix1: Modify All on Group, Definition and Translation (needed because OWD is Private). Alternative: a sharing rule or a wider OWD for those three objects.
- [ ] Confirm the org rule that internal users need `Business_Segment_PC3__c` is still handled by `NotificationTestDataFactory.createUser`.

---

## 2. Gates and decisions that control the work

| Gate | Scope | Exit criterion | Blocks |
|---|---|---|---|
| **G1** | Bell LWC in the real LWR header; Apex callable by external-license users; polling cost; language re-render | Works in representative stores and licenses | Slice 1 go-live |
| **G2** | Field, relationship, role, geography and delegation mappings; legacy NA/EMEA email inventory | Approved mapping and completed S7 FR17 matrix | Workstream C (resolver, entitlement), real `NotificationStoreAccess`, multi-select Definition fields, Store visibility matrix release |
| **G3** | Email sandbox test to User recipients beyond the 5,000/day external allowance; per-transaction limits; deliverability; measured volumes | Exemption confirmed, or a provider chosen | Workstream G (email adapter) design |
| **G4** | Business decisions D01 to D15 (custom-inbox scope change, defaults D14, cross-store scope D11, retention days, polling targets) | Signed off | Preferences defaults, retention, go-live |

### Open items from the design doc
1. Verify the email exemption for your user license (G3).
2. Agree Bell and Email retention periods and the storage budget (proposed: Bell 30 days, Email detail 14 to 30 days, Request tombstone at least as long as the upstream replay horizon).
3. Confirm 5-minute polling and the resulting visibility delay are acceptable.
4. Decide whether Group display text is Custom Labels or business-editable records (the latter adds a localized child object).
5. Confirm team size and availability behind the estimate.
6. Obtain sign-off on the custom-inbox scope change and D01 to D15.

---

## 3. Remaining workstreams

Effort figures are the design doc's person-day ranges for the whole workstream, including work already done in slices 1 and 2. They are not remaining effort.

### A. Schema, permissions, configuration, activation (15 to 22 d): mostly done
Remaining:
- [ ] `Notification_Preference__c` object (see D).
- [ ] Deferred Definition fields: multi-select Stores, Regions, Countries, Roles, Sales Channels (need G2 master-data keys).
- [ ] Request fields: subject, Account and Location references, counters.
- [ ] Page layouts for the five admin objects.
- [ ] Seed more `Notification_Setting__mdt` rows as needed: `MergeToken` registry, `LocaleAlias`, `SourceCapability`, `EventRegistry`, `RetryPolicy` jitter and max attempts.
- [ ] Permission set updates for each new object and field (Support, Config_Editor, Customer).
- [ ] Decision: Group display text as Custom Labels or business-editable child object.

### B. Content renderer, locale, target resolution (8 to 12 d): mostly done
Built: read-time renderer, locale bundle with whole-bundle English fallback, token merge, target validator.
Remaining:
- [ ] Email-side rendering per recipient (Contact preferred language at dispatch, rendered locale and hash on the Delivery).
- [ ] Wire `LocaleAlias` settings end to end and test.
- [ ] Re-check subject access on click (design section 6).

### C. Audience resolver and entitlement service (15 to 25 d): **blocked by G2**
- [ ] Resolver interface keyed by `Audience_Resolver_Key__c` and the `EventRegistry` setting.
- [ ] Entitlement rules: entitlements, geography, roles, store, effective Account.
- [ ] Paged recipient resolution for workers, with `LastProcessedKey__c` as the resume checkpoint (re-scan is safe because `DeliveryKey__c` is unique).
- [ ] Replace the `NotificationStoreAccess.validate` stub (currently format check only) with the membership and effective-Account check.
- [ ] Risk noted in the doc: unclear mappings or complex delegated access add 10 to 25 days.
- **(suggested)** Until G2 lands, build a simple resolver that targets an explicit known user so slices 3 and 4 can be tested end to end.

### D. Preferences, Store visibility, My Profile LWC (14 to 20 d)
- [ ] `Notification_Preference__c`: Contact, Group, `BellChoice__c`, `EmailChoice__c` (Enabled / Disabled / Inherit), version, changed by / time / source, unique Contact + Group.
- [ ] Before-save validator that blocks spoofing, reparenting and key changes.
- [ ] Preferences service: read and save, stale-save conflict using the version, Mandatory groups hidden and changes rejected server-side, explicit defaults required before activation (D14).
- [ ] `StorePreferenceVisibilityPolicy`: evaluate server-side after validating the effective Account. A Store row first needs Contact Web App includes Store AND Account Store Flag true. Then the NA / EMEA matrix in design section 7. Unknown combinations hide pending mapping.
- [ ] My Profile LWC for preference settings.
- [ ] Cross-store preference scope needs D11 sign-off.
- Store controls for a group stay unreleased until the NA/EMEA email inventory and mapping are approved (G2, S7 FR17).

### E. Ingress, request ledger, dispatcher, workers (20 to 30 d)
- [ ] Bulk invocable ingress for Flow and Apex. Validate source, definition and store; pin the active definition; insert Request keyed by source + business event ID.
- [ ] Authenticated Apex REST endpoint. Reject client-supplied recipient lists, HTML, target URLs and Mandatory flags. Payload cap 32 KB (tunable). Return 202 only after durable acceptance, 409 for a conflicting payload on the same event key.
- [ ] OAuth External Client App for the integration identity, scoped by source, event, definition and store.
- [ ] Request state machine: Accepted, Resolving, Dispatching, then Completed, CompletedWithErrors, Rejected or Expired.
- [ ] Dispatcher and workers: page through recipients, insert one Delivery per recipient and channel. Never enqueue one job per recipient.
- [ ] Evaluate step: re-check eligibility and latest preferences. Bell rows become Visible; email rows are claimed.
- [ ] Scheduled sweeper that recovers committed but unprocessed Requests.
- [ ] Kill switches (`NotificationConfig.isKilled`) honored per source and channel. Replay uses the same keys and cannot reset a successful channel to Pending.
- [ ] Redacted diagnostics for validation failures. Fail the source transaction if the outbox insert fails for a business-critical notification (business owner approves softer behavior per trigger).
- [ ] Narrow privileged selectors with allowlisted fields for workers.
- Note: the design estimates up to about 2 minutes to process plus up to 5 minutes for the bell to show it.

### F. Bell inbox (15 to 22 d): code done, integration pending
- [ ] **G1:** place `nimbusNotificationBell` in the real LWR theme header and set its `storeKey`.
- [ ] Assign `Nimbus_Notification_Customer` to the external profile or permission set group.
- [ ] Test with real external-license users, not only `System.runAs`.
- [ ] Verify polling behavior in practice: 5 minutes with jitter, only while the tab is visible, back-off on errors, timer cleared on disconnect, refresh on navigation and language change.
- [ ] Accessibility pass (focus, Escape to close, badge labelling, semantic timestamps).
- [ ] If the header cannot host the component, the doc estimates 5 to 10 extra days or an alternative placement.

### G. Email adapter and delivery state machine (8 to 12 d): depends on G3
- [ ] Adapter behind the `ChannelAdapter` setting (seeded: `Adapter_Email`).
- [ ] Send with Apex messaging to the recipient User, save-as-activity off, rendered per recipient, never combining customers in one message.
- [ ] States: Pending, Claimed, Sending, then Accepted, Suppressed, RetryDue, DeadLetter or Unknown. Record platform acceptance as Accepted, never Delivered.
- [ ] Lease token and expiry for claims.
- [ ] Retries at 1, 5, 15, 60 minutes with jitter (seeded `Retry_Email`), then dead letter. Timeout after a possible send becomes Unknown and needs recorded reconciliation. Never retry beyond expiry.
- [ ] Respect the 10 `sendEmail` calls per transaction limit by batching messages per call.
- [ ] Org-wide sender, authenticated domain, deliverability set to all email per environment.
- [ ] If G3 fails: transactional email provider adapter, 10 to 15 extra days.

### H. Operations (8 to 12 d)
- [ ] Purge jobs in bounded scheduled batches (Bell rows after the visibility window, Email detail, Request tombstones kept per the replay horizon).
- [ ] Dashboards and monitoring: oldest pending age, latency, recipients resolved, suppression reasons, per-channel outcomes, retries, locale fallback, dead-letter rate, email volume, polling call rate, storage growth.
- [ ] Dead-letter replay and support tooling (redacted ledger access, controlled retry).
- [ ] Correlation IDs and redacted error codes in logs.

### I. QA (20 to 30 d)
- [ ] Keep tests T01 to T06, T10 to T12, T14, T15 from design v0.1.
- [ ] Rewrite T07 (inbox scoping, unread, pagination, mark one / all with cutoff, cross-user and cross-store denial), T09 (language change without a new send, read state kept, English fallback), T13 (purge, tombstones kept, nothing shown after purge).
- [ ] Add T16 (poll load, tab visibility, error backoff) and T17 (storage growth vs retention).
- [ ] Security negatives and load tests; UAT support.

### J. Migration and cutover (10 to 15 d)
- [ ] Dry run, preference import, first-wave legacy email producers (each further producer is 2 to 4 days plus UAT). Legacy emails stay unchanged until explicitly migrated.

### K. Delivery overhead (8 to 12 d)
- [ ] CI pipeline, deployment, documentation, handover.

---

## 4. Suggested slice order **(suggested)**

| Slice | Goal | Depends on |
|---|---|---|
| 3 | Ingress (invocable first, REST after) and request ledger, using the slice 2 keys | none |
| 4 | Dispatcher and Bell workers with a stub resolver, kill switches, sweeper. First end-to-end Bell notification | slice 3 |
| 5 | Preferences object, service, validator, My Profile LWC (optional groups first) | D11, D14 decisions |
| 6 | Real resolver, entitlement service, `NotificationStoreAccess`, Store visibility policy, multi-select Definition fields | **G2** |
| 7 | Email adapter, state machine, retries, dead letter | **G3** |
| 8 | Purge jobs, dashboards, support tooling | retention decisions |
| 9 | Hardening (security, load, T16 / T17), UAT, then legacy email migration waves | all above |

Critical path from the design doc: G2 mappings, then resolver (C), then engine (E), then channels (F, G), then hardening. Slices 3 to 5 can proceed in parallel with the G2 work.

---

## 5. Known stubs and constraints

- `NotificationStoreAccess.validate` only checks key format (TODO G1/G2 in source).
- `NotificationGuard.bypass` is a test-only flag used to seed Active fixtures. It must stay `@TestVisible private`.
- Users who activate definitions need both `Nimbus_Notification_Config_Editor` and `Nimbus_Notification_Activator`.
- All framework objects use Private OWD. Customers have no object access to Request or Delivery, so every read and write goes through Apex.
- Hash keys are SHA-256 hex stored as Text(64) unique External IDs. Identity fields are frozen after insert.
- Recipients are Salesforce Users, so the 5,000/day external-address cap is expected not to apply. This is unverified until G3.
- Config text is never executed as code. No secrets in custom objects or Custom Metadata.

---

## 6. Estimate reference (from the design doc)

Headline: 163 to 250 person-days (plus or minus 30% until Phase 0 ends), about 3.5 to 5.5 months with two developers or 3 to 4 months with three. Re-baseline after Phase 0 using the real mappings, email inventory and volumes.

Not included: manual send console (12 to 20 d), additional external source adapters (3 to 6 d each), email provider if G3 fails (10 to 15 d), SMS, mobile push, Color integration, translation authoring, data cleanup, training.
