# Nimbus Notification Framework: Recommended Design and Build Estimate

*17 October 2026. Draft for architecture and product review. Platform: Salesforce B2B Commerce on Experience Cloud LWR. Builds on the requirements evaluation and technical design v0.1, revised by the decisions below.*

## 1. Summary

Build the framework on custom objects, Apex and LWC. Bell notifications are rows in `Notification_Delivery__c` that a custom LWC polls every 5 minutes. Email is sent from Apex to the recipient's User record. Native Salesforce custom notifications are not used.

Three things need sign-off before build:

1. **Custom inbox replaces the native bell channel.** The BRD asks for native retention and read state (decision D06). This design defines its own retention and read state instead.
2. **Email exemption.** Single emails to Salesforce User records are expected not to count against the 5,000/day external-address allowance. This must be verified in a sandbox (gate G3).
3. **Business decisions D01 to D15** from the requirements evaluation, especially default preferences (D14) and cross-store preference scope (D11).

**Estimate headline:** 163 to 250 person-days for a production-ready MVP (Bell and Email, automatic notifications, preferences, Store visibility rules). That is roughly 3.5 to 5.5 months elapsed with two developers, or 3 to 4 months with three. It is a rough order of magnitude (plus or minus 30%) until the Phase 0 gates finish. See section 12.

## 2. What changed from technical design v0.1

| Area | v0.1 | Recommended |
| --- | --- | --- |
| Bell channel | Native Custom Notifications, Notifications API, conditional render context | Inbox rows in `Notification_Delivery__c`, polled by the LWC |
| Objects | 11 | 6 (plus Custom Metadata Types) |
| Removed objects | n/a | Render Context, Audience Work, Delivery Attempt, Definition Store, Audience Value; Definition and Revision merged |
| Prototype P1 | Blocking: native correlation and locale round-trip | Smaller gate G1: header placement, external-user Apex access, polling |
| Native bell limits | 10,000 sends/hour, native pruning, text caps | None apply; own retention and storage budget |
| Bell duplicates | Ambiguous send outcomes possible | Database unique key; Unknown state applies to email only |
| Email | Native versus provider go/no-go on the 5,000 cap | Send to User records; confirm exemption in sandbox; provider only if the test fails |
| Scoped count and pagination | Workarounds over the native collection | Plain SOQL filters |

## 3. Architecture

1. **Source event.** A Flow or Apex transaction calls the bulk invocable ingress, or an approved external system calls the authenticated Apex REST endpoint.
2. **Accept.** Validate source, definition and store. Pin the active definition version. Insert `Notification_Request__c` keyed by source and business event ID.
3. **Resolve.** Workers page through eligible recipients (entitlements, geography, roles, store) and insert one `Notification_Delivery__c` per recipient and channel, with a unique `DeliveryKey__c`.
4. **Evaluate.** Re-check eligibility and the latest preferences. Bell rows become Visible. Email rows are claimed for sending.
5. **Send (email only).** Apex sends to the User and records the outcome.
6. **Display.** The LWC polls Apex. Apex returns the current user's visible Bell rows, rendered in the current site language.

Principles: business configuration lives in custom objects and technical mappings in Custom Metadata Types; configuration text is never executed as code; all authorization is server-side; settings visibility is separate from delivery eligibility; legacy emails stay unchanged until explicitly migrated.

## 4. Data model

| Object | Purpose and key fields |
| --- | --- |
| `Notification_Group__c` | `Key__c` unique; Name; Source Application; Preference Type (Optional/Mandatory); Eligibility Type and Description; Visibility Policy Key; default Bell and Email choice; Active; Sort Order; Policy Version. Owns the Optional/Mandatory policy; definitions inherit it. |
| `Notification_Definition__c` | `Key__c` + `Version__c` unique pair; Group lookup; Source Application (must match the group); Automatic/Manual; Status (Draft/Active/Retired); trigger description, source and event type; Audience Resolver Key; channels; target route; expiry; required-token schema; Stores, Regions, Countries, Roles and Sales Channels as multi-select picklists (master-data references as validated key lists); activated by/at. Active versions are immutable; an edit creates a new version; one Active version per Key. |
| `Notification_Translation__c` | Definition lookup; Locale; title, message, subject, body, action label, supporting text; completeness flag; approval status; unique Definition + Locale. English is required. |
| `Notification_Preference__c` | Contact; Group; `BellChoice__c` and `EmailChoice__c` (Enabled/Disabled/Inherit); version; changed by, time and source; unique Contact + Group. |
| `Notification_Request__c` | Source App; business event ID; `EventKey__c` unique; payload hash; pinned Definition lookup; store; subject, Account and Location references; minimized context; status; correlation ID; received and expiry times; counters; `LastProcessedKey__c` (resolver checkpoint). |
| `Notification_Delivery__c` | Request; Contact; recipient User; Channel (Bell/Email); `DeliveryKey__c` unique; status; reason; attempt count, last error code, next retry, lease token and expiry (email); evaluated preference and policy version; `ReadAt__c` and `SeenAt__c` (Bell); rendered locale and hash (Email). One row per request, recipient and channel. |

**Custom Metadata Types** hold event and resolver registry, allowed merge tokens, source capabilities, locale aliases, channel adapter configuration, retry bounds and kill switches. No secrets in either model.

**Rules.** Hash keys are Text(64) unique External IDs, with their constituent fields kept for audit. Use lookups with restricted delete, not master-detail to Account or Contact. Set OWD to Private for all framework objects. Never store recipient lists in long text.

**Group display text.** Default to Custom Labels referenced by Group Key. If the business must edit group text without a deployment, add a small localized child object, which makes 7 objects. Translation Workbench does not translate custom-object record values.

**Optional split.** If admins need a stable parent record page for a definition, split Definition and Revision as in v0.1. Nothing else in this design changes.

## 5. Processing and reliability

**Request states:** Accepted, Resolving, Dispatching, then Completed, CompletedWithErrors, Rejected or Expired.

**Delivery states:**

- Bell: Pending, Visible, then Expired or Suppressed. There is no callout, so no lease or Unknown state.
- Email: Pending, Claimed, Sending, then Accepted, Suppressed, RetryDue, DeadLetter or Unknown.

**Identity keys:**

```text
EventKey    = hash(sourceApplication | businessEventId)
DeliveryKey = hash(EventKey | definitionKey | recipientUserId | channel | scopeKey)
PreferenceKey = Contact + Group
```

**Rules:**

- The committed Request is the handoff. Sending is asynchronous. Never enqueue one job per recipient. A scheduled sweeper recovers committed, unprocessed requests.
- Validation failures produce a redacted diagnostic and no send. If the outbox insert fails for a business-critical notification, fail the source transaction; the business owner approves any softer behavior per trigger.
- A restarted resolver re-scans. The unique `DeliveryKey__c` absorbs duplicates, and `LastProcessedKey__c` only speeds it up.
- Email retries at 1, 5, 15 and 60 minutes with jitter, then dead letter. A timeout after a possible send becomes Unknown and needs recorded reconciliation. Never retry beyond expiry.
- Per-source and per-channel kill switches. Replay uses the same keys and cannot reset a successful channel to Pending.
- **Guarantee:** creation of rows is exactly-once by database uniqueness, so Bell visibility is exactly-once. Email is at-most-once automatically, with residual risk only on ambiguous outcomes.

## 6. Bell inbox and LWC

`NotificationInboxController` is `with sharing`, uses user-mode queries and returns DTOs only:

| Method | Behavior |
| --- | --- |
| `getSummary(storeKey)` | Unread count (capped display) and latest timestamp. This is the poll call. |
| `listMine(storeKey, lang, cursor, limit)` | Current user's Visible Bell rows, newest first, rendered in the chosen language. |
| `markRead(ids)` | Marks the user's own rows read. |
| `markAllRead(storeKey, cutoff)` | Marks rows in the current store scope up to the cutoff, so later arrivals stay unread. |
| `markSeen(cutoff)` | Updates seen state for the badge. |

**Rules.** Derive the User from the session and never accept a user or Contact ID. Validate the store key against the user's membership and effective Account. Validate the language against supported locales, falling back to English. Customers have no object permissions, so all reads and read-state writes go through Apex.

**Rendering at read time.** Resolve Delivery to Request to Definition to Translation for the chosen locale. Use the complete bundle or fall back to English as a whole; never mix languages in one notification. Dynamic values and the target are unchanged, and the action label comes from the chosen bundle. Validate target URLs against allowlisted routes (no `javascript:`, protocol-relative URLs or open redirects). After access is revoked, return a generic unavailable message. Re-check subject access when the user clicks.

**LWCs:** `nimbusNotificationBell`, `nimbusNotificationTray`, `nimbusNotificationItem`, placed in the existing theme header. Include loading, empty and error states, keyboard focus, Escape to close, accessible unread badge and semantic timestamps.

**Polling.** Every 5 minutes with jitter, only while the tab is visible, calling `getSummary` only. Load the list when the tray opens. Also refresh on navigation and language change. Back off on errors and clear the timer on disconnect. Do not use `lightning/empApi`, which is not supported in storefronts. Calls per hour are roughly visible sessions multiplied by 12.

**Latency.** A notification can take up to about 2 minutes to process plus up to 5 minutes to appear. Refreshing on tray open makes it immediate when the user looks.

## 7. Preferences and Store visibility

- Preferences are one row per Contact and Group, with independent Bell and Email values, shared across entitled Accounts and Locations. Cross-store meaning needs D11 sign-off.
- Mandatory groups are hidden and any attempt to change them is rejected server-side. Optional defaults must be explicit before activation (D14).
- Stale saves return a refresh-required conflict using the preference version.
- Store visibility is evaluated server-side by `StorePreferenceVisibilityPolicy` after validating the current effective Account. It is a settings rule, not an email filter, and it does not erase saved preferences.

Every Store row first requires Contact Web App includes Store AND the effective Account Store Flag is true.

| Group | Region | Additional conditions | Visibility |
| --- | --- | --- | --- |
| Approval Status | North America | Role Customer Lead or Customer Manager AND Account feature `24HG` | Show if all pass |
| Approval Status | EMEA | Account Type Customer AND role Customer Manager or Customer User AND Contact Approval Process Required | Show if all pass |
| Billing, Order Status | North America | None | Show |
| Billing, Order Status | EMEA | Irrespective of role | Hide |
| Any Store group | Other or unknown | No approved matrix | Hide pending mapping |

Controls for a group stay unreleased until the existing NA/EMEA email inventory and mapping are approved (S7 FR17).

## 8. Email

- Send with Apex messaging using the recipient's User as the target, with save-as-activity off. Render per recipient. Never combine different customers in one message.
- Language is the Contact's Preferred Language at dispatch, with whole-bundle English fallback.
- Use the approved org-wide sender, authenticated domain and email deliverability set to all email in each environment.
- Platform acceptance is recorded as Accepted, never Delivered.
- **Limits.** Apex allows 10 `sendEmail` calls per transaction, so batch messages per call and keep worker batches small. The 5,000/day external-address cap is not expected to apply to User recipients. Confirm this in gate G3. A transactional email provider behind the same adapter is needed only if the test fails.

## 9. Security

| Actor | Boundary |
| --- | --- |
| Guest | No access. |
| Nimbus customer | Apex-only access to their own inbox rows and own preferences. No object access to Request or Delivery. |
| Configuration editor | Creates and edits draft groups, definitions and translations. Cannot activate. |
| Activator | Separate custom permission; activation is audited. |
| Integration identity | OAuth External Client App, source-scoped to allowed applications, events, definitions and stores. |
| Worker | Narrow privileged selectors with allowlisted fields. Not exposed to UI. |
| Support | Redacted ledger access and controlled retry. |

- Use explicit sharing and explicit user-mode access. `with sharing` alone is not field-level enforcement.
- A before-save validator protects preference rows from spoofing, reparenting and key changes.
- External ingress rejects client-supplied recipient lists, HTML, target URLs and Mandatory flags. Payload cap is 32 KB, tunable. Return 202 only after durable acceptance, 409 for a conflicting payload on the same event key.

## 10. Retention, capacity and monitoring

```text
Daily delivery rows = events/day x eligible recipients/event x enabled channels
Polling calls/hour  = visible sessions x 12
Storage             = daily rows x retention days x about 2 KB
```

Illustration only: 2,000 events/day x 20 recipients x 2 channels = 80,000 rows/day. At about 2 KB per record that is about 160 MB/day, or about 4.8 GB over 30 days. Agree real inputs and check against org data storage.

**Proposed retention (to agree):**

- Bell rows: the visibility window (30 days proposed), then purge in bounded scheduled batches.
- Email rows: 14 to 30 days of detail.
- Request: keep a minimal tombstone (event key, hash, status) at least as long as the upstream replay horizon and until its Bell rows are purged.

**Monitor:** oldest pending age, processing latency, recipients resolved, suppression reasons, per-channel outcomes, retries, locale fallback, dead-letter rate, email volume, polling call rate and storage growth. Logs carry correlation IDs and redacted error codes.

**Service targets (to confirm, not SLAs):** 95% of eligible requests have Bell rows visible or email accepted within 2 minutes at normal volume; the bell reflects them within the 5-minute poll; preference read and save p95 under 1 second; tray open p95 under 2 seconds.

## 11. Verification and release gates

| Gate | Scope | Exit criterion |
| --- | --- | --- |
| G1 (replaces P1) | LWC in the real LWR header; Apex callable by external-license users; polling cost; language re-render | Works in representative stores and licenses |
| G2 | Field, relationship, role, geography and delegation mappings; legacy NA/EMEA email inventory | Approved mapping and completed S7 FR17 matrix |
| G3 | Email sandbox test to User recipients beyond the external allowance; per-transaction limits; deliverability; measured volumes | Exemption confirmed or provider chosen |
| G4 | Decisions D01 to D15, including the custom-inbox scope change, defaults, cross-store scope, retention days and polling-based targets | Signed off |

**Tests.** Keep T01 to T06, T10 to T12, T14 and T15 from v0.1. Rewrite these:

- **T07:** inbox returns only the current user's rows for the right store; unread count; pagination; mark one and mark all with cutoff; cross-user and cross-store denial.
- **T09:** a received bell item changes language when the site language changes, without a new send, with read state kept and English fallback.
- **T13:** purge job, tombstones preserved, nothing displayed after purge.

Add T16 (poll load, tab visibility, error backoff) and T17 (storage growth against retention). Use real external-user sandbox tests, not only `System.runAs`.

## 12. Build estimate

**Scope:** Bell and Email, automatic notifications through Flow/Apex ingress and the external REST endpoint, configuration objects and admin UI, translations, preferences with Store visibility, support tooling, two or three representative notifications end to end, and migration of the first wave of legacy emails.

**Assumed team:** 2 Salesforce developers (Apex and LWC), 1 QA engineer, architect at about 50%, BA or product owner at about 25%, plus business data owners for mappings and the email inventory. Developer lines include unit tests. The QA line covers integration, security, load and UAT support.

| Workstream | Person-days |
| --- | --- |
| Phase 0 gates: G1 prototype, mapping analysis, email inventory support, email sandbox test, decision workshops | 22 to 38 |
| A. Schema, permissions, configuration objects, validation, activation, admin app, seeding | 15 to 22 |
| B. Content renderer, locale and target resolution, token validation | 8 to 12 |
| C. Audience resolver and entitlement service | 15 to 25 |
| D. Preferences service, Store visibility policy, My Profile LWC | 14 to 20 |
| E. Ingress (invocable and REST), request ledger, dispatcher and workers, dedup, recovery, kill switches | 20 to 30 |
| F. Bell inbox: Apex controller, three LWCs, polling, header integration, accessibility | 15 to 22 |
| G. Email adapter and delivery state machine | 8 to 12 |
| H. Operations: dashboards, dead-letter replay, purge jobs, monitoring | 8 to 12 |
| I. QA: integration, security negatives, load, UAT support | 20 to 30 |
| J. Migration and cutover: dry run, preference import, first-wave producers | 10 to 15 |
| K. Delivery overhead: pipeline, deployment, documentation, handover | 8 to 12 |
| **Total** | **163 to 250** |

**Elapsed time:**

| Scenario | Phase 0 | Build | Hardening, UAT, cutover | Total |
| --- | --- | --- | --- | --- |
| 2 developers | 2 to 3 weeks | 10 to 16 weeks | 3 to 4 weeks | 15 to 23 weeks (3.5 to 5.5 months) |
| 3 developers | 2 to 3 weeks | 7 to 10 weeks | 3 to 4 weeks | 12 to 17 weeks (3 to 4 months) |

A third developer gives diminishing returns because the audience resolver (C) and the engine (E) are on the critical path.

**Critical path:** G2 mappings, then the resolver (C), then the engine (E), then the Bell and Email channels (F, G), then hardening. Schema, translations, preferences and the inbox UI (against a stubbed controller) can run in parallel.

**Milestones:** M0 gates; M1 foundations (schema, configuration, translations, preferences UI); M2 first end-to-end Bell and Email for representative notifications; M3 hardening, security and load tests, UAT; M4 legacy email migration in waves.

**Not included (separate rough estimates):**

| Item | Rough effort |
| --- | --- |
| Manual send console (product definition first) | 12 to 20 days |
| Each additional external source or trigger adapter | 3 to 6 days |
| Each legacy email producer beyond the first wave | 2 to 4 days plus UAT |
| Transactional email provider, if the sandbox test fails | 10 to 15 days |
| SMS, mobile push, Color integration, translation authoring, data cleanup, training | Not estimated |

My judgment is that this design is roughly 20 to 30% less effort than v0.1, mainly from removing native correlation, render context, checkpoints and attempt history. That figure is not measured.

**Estimate risks:**

| Risk | Effect |
| --- | --- |
| Unclear field mappings or complex delegated access | Plus 10 to 25 days in workstream C |
| LWR theme header cannot host the component as planned | Found in G1; plus 5 to 10 days or alternative placement |
| Email exemption fails for your user license | Plus 10 to 15 days for a provider adapter |
| Many legacy email producers | Plus 2 to 4 days each |
| Volumes above assumptions | Plus 5 to 10 days for purge, storage and archive work |
| Heavier translation approval workflow | Plus 5 to 8 days |

Confidence is plus or minus 30% until Phase 0 ends. Re-baseline then, using the real mappings, email inventory and volumes.

## 13. Open items

1. Verify the email exemption for your user license in a sandbox (G3).
2. Agree Bell and Email retention periods and the storage budget.
3. Confirm that 5-minute polling and the resulting visibility delay are acceptable.
4. Decide whether Group display text is Custom Labels or business-editable records.
5. Confirm the team size and availability behind the estimate.
6. Obtain sign-off on the custom-inbox scope change and decisions D01 to D15.
