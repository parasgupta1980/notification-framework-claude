# Nimbus Notification Framework: Implementation Handoff

*18 October 2026. Slice 1 (bell inbox) has passed deployment validation. This document lets a new session continue the build.*

## 1. Context

- **Goal:** build the Nimbus notification framework (bell and email) on Salesforce B2B Commerce, Experience Cloud LWR, using custom objects, Apex and custom LWCs. Native Salesforce custom notifications are not used.
- **Governing design:** [Nimbus Notification Framework: Recommended Design and Build Estimate](https://claude.ai/artifact/7JxPeUnyqZrkAQAoSff88C) (17 October 2026). It supersedes technical design v0.1 where they differ.
- **Decided by you:** `Notification_Delivery__c` is a custom object that the custom LWC bell polls every 5 minutes. Recipients are Salesforce User records, so the 5,000/day external-address email limit is expected not to apply (still to be verified, gate G3).
- **Code location:** SFDX project `nimbus-notifications` (zip: `nimbus-notifications-slice1.zip`). Container files do not persist between sessions, so keep the project in your own repository and give the new session the zip or the repo.

## 2. Completed: slice 1 (design workstreams A and F, plus the renderer from B)

Status: **deployment validation succeeded** after three rounds of fixes, including Apex test coverage.

### Data model (5 of the 6 objects, all with Private sharing)

| Object | Notes |
| --- | --- |
| `Notification_Group__c` | `Key__c` unique, Preference Type, default Bell/Email flags, Active, Sort Order, Policy Version, Visibility Policy Key |
| `Notification_Definition__c` | `Key__c` + `Version__c`, unique `VersionKey__c`, Group lookup, Mode, Status (Draft/Active/Retired), channel flags, Target Route, Expiry Days, Required Tokens, Audience Resolver Key |
| `Notification_Translation__c` | Definition lookup, Locale, unique `DefinitionLocaleKey__c`, title, message, action label, email subject/body, completeness and approval status |
| `Notification_Request__c` | auto-number, Source App, Business Event Id, unique `EventKey__c`, payload hash, pinned Definition, Store Key, Account, minimized context JSON, status, correlation Id, received/expiry times, `LastProcessedKey__c` |
| `Notification_Delivery__c` | auto-number, Request, Recipient User (SetNull) and Contact, Channel, unique `DeliveryKey__c`, status (Bell and Email states), Store Key, Visible/Expires/Read/Seen times, email retry and lease fields, rendered locale |

### Apex

- `NotificationInboxController`: `getSummary`, `listMine` (keyset cursor), `markRead`, `markAllRead` (cutoff), `markSeen`. The user always comes from the session.
- `NotificationInboxSelector`: runs **without sharing**, hard-scoped to the running user with a fixed field list. It also performs the read-state DML.
- `NotificationRenderer`: renders at read time, chooses a whole translation bundle by locale (exact, language only, `en_US`, `en`), merges `{{token}}` values from the request context.
- `NotificationTargetValidator`: allows same-site relative paths only.
- `NotificationStoreAccess`: **stub** (format check only).
- `NotificationInboxDto`: Summary, Item, InboxPage.
- Tests: `NotificationInboxControllerTest` (10 tests) and `NotificationTestDataFactory`.

### LWC and configuration

- `nimbusNotificationBell` (5-minute poll with jitter, visible tab only, backoff, badge, keyboard and focus handling), `nimbusNotificationTray`, `nimbusNotificationItem`. The bell is exposed to Experience Builder with a `storeKey` property.
- 12 Custom Labels (`Nimbus_Notif_*`).
- Permission sets: Config Editor, Activator (custom permission `Nimbus_Notification_Activate`), Support, Customer (Apex-only).

### Decisions and deviations from the design

1. **Selector in system mode.** The design says user-mode queries but also says customers have no object access to Delivery. These conflict, so the selector is system mode with strict per-user scoping. Revisit only if you prefer to grant customers read access.
2. **Recipient User lookup is SetNull**, because Salesforce does not allow restrict-on-delete to User. Rows survive user deletion with a blank recipient.
3. **Reserved words:** `Page` and `merge` are reserved in Apex, hence `InboxPage` and `mergeTokens`.
4. **Org rule:** your org requires `Business_Segment_PC3__c` on internal users. The test factory fills it dynamically (first active picklist value, or `TEST` for text).
5. **Simplified objects.** Several design fields were deliberately left out of slice 1: on Group the eligibility type and description; on Definition the Stores, Regions, Countries, Roles and Sales Channels multi-selects, trigger description, source and event type, activated by/at; on Request the subject, Location and counter fields. Add them with the workstreams that need them.

## 3. Remaining work

### Phase 0 gates (do these first)

| Gate | Task | Why it matters |
| --- | --- | --- |
| G1 | Put `nimbusNotificationBell` in the real LWR theme header; test as **external-license users** in a sandbox (not only `System.runAs`); measure polling and language re-render | Confirms the component placement and that the Apex is callable by customers |
| G2 | Approve field, role, geography and delegation mappings; complete the legacy NA/EMEA email inventory (S7 FR17 matrix) | Blocks the audience resolver (critical path) and Store visibility |
| G3 | Sandbox test: send single emails to User recipients beyond the 5,000/day external allowance | Decides native sending versus a provider (10 to 15 extra days) |
| G4 | Sign-off on decisions D01 to D15, the custom-inbox scope change, retention days, polling-based service targets | Required before activation of production definitions |

### Build workstreams (design section 12)

- **A (finish):** admin app, tabs, page layouts, seeding; activation validation (one Active version per Key, Active versions immutable, audited activation using the custom permission); the remaining object fields listed above; Custom Metadata Types (event and resolver registry, merge tokens, source capabilities, locale aliases, channel adapters, retry bounds, kill switches).
- **A/B:** hash-key generation for `EventKey__c`, `DeliveryKey__c`, `DefinitionLocaleKey__c` (currently plain unique fields, nothing fills them yet); required-token validation; locale alias handling.
- **C:** audience resolver and entitlement service (largest risk, depends on G2).
- **D:** `Notification_Preference__c` (Contact + Group, unique), preferences service with version conflicts, `StorePreferenceVisibilityPolicy`, My Profile LWC, before-save validator against spoofing and reparenting. Needs D11 and D14 decisions.
- **E:** invocable Flow/Apex ingress, authenticated REST endpoint (202 after durable acceptance, 409 on conflicting payload, 32 KB cap), request ledger, dispatcher and workers (never one job per recipient), sweeper, dedup, kill switches.
- **G:** email adapter and delivery state machine (retries at 1, 5, 15, 60 minutes with jitter, dead letter, Unknown state, 10 `sendEmail` calls per transaction).
- **H:** operations dashboards, dead-letter replay, purge jobs (Bell 30 days proposed, Email 14 to 30 days, Request tombstones), monitoring.
- **I:** remaining tests T01 to T06, T10 to T12, T14 to T17 (poll load, storage growth); security negatives; load tests.
- **J:** migration and cutover of the first wave of legacy emails.
- **Replace the `NotificationStoreAccess` stub** with the approved membership and effective-Account check once G2 is done.

### Suggested order

1. G1 sandbox test of slice 1 (cheap, and decides whether the layout holds).
2. In parallel: G2 mapping workshops and G3 email test.
3. Hash-key generation, activation validation and the remaining schema fields.
4. Preferences (D) and the ingress and request ledger (E), which can run against the stubbed audience.
5. Resolver (C), then dispatcher and workers, then email (G), then operations and purge (H), then hardening and migration.

## 4. Open decisions (from the design, section 13)

1. Email exemption for your user license (G3).
2. Bell and Email retention periods and storage budget.
3. Whether 5-minute polling and the resulting visibility delay are acceptable.
4. Group display text: Custom Labels (default) or business-editable records (adds a 7th object).
5. Team size and availability behind the estimate (163 to 250 person-days, plus or minus 30%).
6. Sign-off on the custom-inbox scope change and D01 to D15.

## 5. Starter prompt for the new session

> Continue the Nimbus notification framework build. Design: https://claude.ai/artifact/7JxPeUnyqZrkAQAoSff88C. Slice 1 (bell inbox, five objects, inbox controller, three LWCs, permission sets) has passed deployment validation; I am attaching the SFDX project zip and the handoff document. Next I want to build: \[state the next workstream, for example Notification\_Preference\_\_c and the preferences service, or the ingress and request ledger\]. Our org enforces a validation rule requiring Business\_Segment\_PC3\_\_c on internal users, which the test factory already handles.
