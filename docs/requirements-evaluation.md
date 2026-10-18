# Nimbus notification framework: requirements evaluation

**Date:** 17 October 2026  
**Status:** Revised to six custom objects following user review; custom-object inbox architecture confirmed; remaining policy resolutions proposed.  
**Target:** Salesforce B2B Commerce on Experience Cloud LWR.  
**Companion:** [Technical design](technical-design.md).

## 1. Assessment

The requirements describe a reusable notification service, not merely a bell component. Salesforce provides notification publication, notification retrieval/read state, email delivery, automation and security primitives. Nimbus still needs configuration, audience resolution, Contact-level grouped preferences, translation orchestration, reliable processing, and an LWR presentation layer.

Proceed with a **custom `Notification__c` publication object and custom LWR notification component**, as confirmed by the user after reviewing the initial design. Secure Apex returns recipient-specific entries rendered in the current site language from a pinned template revision and immutable dynamic values. This removes the native-to-custom correlation feasibility risk.

This decision supersedes B §5.2.1's native channel requirement and B §4/§7.1's platform-controlled retention assumptions. The source PDFs remain unchanged; this evaluation records the authorized design amendment. Nimbus now implements read/seen state, expiry, retention, cleanup and storefront isolation. A proposed 30-day retention default still needs policy and volume confirmation.

The implementation model is reduced from twelve to **six custom data objects**: Group, Definition, Translation, Preference, Request and Notification. Definition versions are rows in the same object. Each recipient Notification combines independent Bell/Email processing state with inbox/read state; only Published Bell entries are exposed to the LWC. Request remains the durable event record for failures before audience expansion and resumable processing. Existing standard/entitlement objects are reused; technical metadata is limited to deployment-owned mappings.

The workspace contains an SFDX starter with empty metadata directories and API version 67.0. No existing Nimbus implementation, field mappings, external-user license, installed bell component, email inventory, or connected-org configuration was available in the source reviewed. This assessment is document-based; it does not claim an org inspection or working prototype.

## 2. Source register

All 11 supplied PDFs were extracted. Image-only bell and preferences mockups were also visually inspected. Page references below refer to PDF pages, not printed business-section numbers.

| ID | Source | Relevant coverage |
| --- | --- | --- |
| B | [Notification Center (BRD)](Notification%20Center%20%28BRD%29.pdf) | v0.3 draft; scope pp. 3–6; requirements pp. 6–13; assumptions/risks pp. 14–15 |
| S1 | [Create and Maintain Notification Definitions](1.%20Create%20and%20Maintain%20Notification%20Definitions.pdf) | Central definitions, Automatic/Manual, validation, languages; pp. 1–4 |
| S2 | [Configure Audience and Customer Segmentation](2.%20Configure%20Audience%20and%20Customer%20Segmentation.pdf) | Geography, roles, Direct/Indirect, related/delegated access; pp. 1–4 |
| S3 | [Generate Automatic Notifications](3.%20Generate%20Automatic%20Notifications.pdf) | Separate triggers, common interface, eligibility/preferences, failure logging; pp. 1–4 |
| S4 | [Deliver Notifications through bell (in-app) and email](4.%20Deliver%20Notifications%20through%20bell%20%28in-app%29%20and%20email.pdf) | Tray mockup p. 3; channels/navigation/languages pp. 4–7 |
| S5 | [Manage Notification preferences in Nimbus](5.%20Manage%20Notification%20preferences%20in%20Nimbus.pdf) | My Profile mockup p. 2; Contact-wide preferences pp. 3–5 |
| S6 | [Support multiple languages for notifications](6.%20Support%20multiple%20languages%20for%20notifications.pdf) | Email Contact language; bell current site language; atomic English fallback; pp. 1–3 |
| S7 | [Notification Preferences for Store](7.%20Notification%20Preferences%20for%20Store.pdf) | Exact NA/EMEA visibility matrix; UI-only constraint; pp. 1–3 |
| S8 | [Create Notification Groupings](8.%20Create%20Notification%20Groupings.pdf) | Group-level Optional/Mandatory; mandatory hidden; pp. 1–3 |
| NT | [Notification Template](Notification%20Template.pdf) | Application, group, content, trigger, storefront, country, role, channels; pp. 1–4 |
| GT | [Notification Grouping Template](Notification%20Grouping%20Template.pdf) | Group metadata, policy and conditional eligibility; pp. 1–3 |

## 3. Conflicts and proposed resolutions

The user-confirmed custom inbox decision takes precedence over the draft BRD where noted. Other specific stories are treated as proposed refinements of the draft BRD. Their numbering alone does not prove approval or chronological precedence. Record acceptance of these resolutions in the implementation backlog.

| ID | Evidence / ambiguity | Proposed baseline | Impact / decision owner |
| --- | --- | --- | --- |
| D01 | B §5.1.1 and S1 BR6 place preference type on definition; S8 BR3–5 prohibit definition overrides | Group owns Optional/Mandatory; every definition references one group and inherits policy | Product Owner: accept S8 refinement |
| D02 | S5 AC4 implies a visible, disabled mandatory option; S8 AC4 says mandatory groups are not displayed | Hide mandatory groups entirely; reject attempts to change their preferences server-side | Product Owner / UX |
| D03 | S5 BR7 links preferences to a definition; S8 BR7 applies one choice to all group members | Unique Contact + Group preference with independent Bell and Email values; definition association is through its group | Product Owner / architect |
| D04 | NT includes SMS and Color; B §4 and S4 BR8 exclude these deliveries | Allow only Bell and Email activation in MVP; Color source integration remains deferred | Product Owner; no implicit scope expansion |
| D05 | S1 supports Manual definitions, while B and S3 prioritize automatic processing | Persist Automatic/Manual type now; manual send UI, approvals and scheduling remain a separate increment unless explicitly included | Product Owner to define manual-send MVP scope |
| D06 | B assumes native channel/retention; user has confirmed a custom object and LWC for dynamic translation | Resolved architecture: `Notification__c` is the authoritative inbox; custom read/seen, expiry and cleanup; render pinned content at display time | Confirmed by user. Retention duration and operating policy remain open; P1 validates implementation, not native feasibility |
| D07 | S7 FR15–16 restrict Store rules to settings visibility and preserve email logic; general service checks eligibility/preferences | Separate settings visibility from delivery eligibility; preserve legacy email producers until each is explicitly onboarded | Product Owner + legacy email owners; blocking migration matrix |
| D08 | NT says dependent picklist for topic; S8 introduces independently maintained grouping records | Filtered Group lookup constrained by Source Application; validation enforces application match | Architect; documented physical-model deviation |
| D09 | NT names “Order Approval”; S7/GT use “Approval Status”; mockup splits requests/responses | Stable group key `STORE_APPROVAL_STATUS`; display label and membership approved in email inventory | Product Owner; avoid accidental duplicate groups |
| D10 | NT lists Stock; GT omits Stock; role names differ across documents | One application/role vocabulary, including Stock only when approved and mapped | Master-data owner |
| D11 | S5 gives Contact-wide preferences; NT scopes delivery by multiple storefronts | Preference remains Contact + Group, shared across entitled Accounts/Locations and stores using that group; delivery remains store-scoped | Product Owner to confirm cross-store preference semantics |
| D12 | S7 uses “associated Account” and “user region”; users may have many entitled Accounts | Proposed UI uses validated effective Account; delivery uses event Account/Location, never browser selection | Product Owner + access-data owner; confirm geography source |
| D13 | Target URL is optional; custom inbox has no native navigation-target constraint | Missing URL produces a non-navigable notification with no action label; configured URLs remain unchanged across languages | Design default for UX review |
| D14 | Defaults, read/seen semantics and consent policy are undefined | Require explicit channel defaults per optional group before activation; separate mandatory classification from consent/suppression | Product Owner / communication-policy owner |
| D15 | “No duplicates” spans database publication and external Email delivery | Unique recipient key plus atomic Bell status change on the same Notification prevents duplicate Bell entries; quarantine ambiguous Email sends rather than blindly retry | Architect / operations; external Email receipt is not an exactly-once guarantee |
| D16 | User requests no more than 5–6 custom objects; earlier model used twelve | Six-object baseline; version rows in Definition; Bell/Email states on Notification; targeting fields on Definition; cursor/error fields on Request; shared Translation object for Group and Definition | Applied in v0.3. No full per-attempt history or parallel audience-partition engine in MVP; no additional logging object |

## 4. Functional fit and traceability

Test IDs are specified in technical design §13. “Custom” means Nimbus implementation on platform, not a separate external service.

| Requirement | Fit / implementation | Verification |
| --- | --- | --- |
| B §5.1.1; S1 AC1–6; NT | Custom configuration objects, controlled keys, required fields, immutable version rows in Definition, supported trigger and channel registry | T01, T02 |
| S1 AC7–10; S4 AC7–10; S6 FR1–14 | Versioned English/translated content; recipient-specific email language; display-time bell renderer; complete-bundle fallback; unchanged dynamic values and target | T09, T10; P1 vertical slice |
| B §5.1.2/5.2.4; S2 AC1–7 | Shared resolver over authorized Account/Location relationships; AND across dimensions, OR within selected values; deduplicate recipient | T03, T04 |
| B §5.1.3/5.2.2; S3 AC1–6 | Bulk invocable ingress + durable request; event/definition validation; resumable Request cursor and independent channel state on recipient Notification | T02, T05, T06 |
| B §5.2.5 | Authenticated external ingress with source/definition/store authorization, business event ID, versioned payload contract | T12 |
| B §5.1.4/5.2.6; S4 AC1–6; amended B §5.2.1 per D06 | Custom inbox publisher + email adapter; custom LWR bell retrieves authorized localized object data through Apex | T07, T08; P1, P3 gates |
| B §5.1.5/5.2.3; S5 AC1–7 | My Profile component; private Contact + Group rows; independent channels; latest committed preference at dispatch | T05, T11 |
| B §5.1.6; S8 AC1–5; GT | Group is independent parent; inherited policy; mandatory hidden; optional group choice covers all children | T01, T05, T11 |
| S7 FR1–17 | Dedicated Store visibility policy and completed NA/EMEA existing-email mapping before releasing corresponding controls | T11, T15; P2 gate |
| B §5.3.1 | Server-side authorization, least privilege, data minimization, safe navigation, per-contact record sharing | T03, T04, T12 |
| B §5.3.2 | Stable contracts and channel/resolver abstractions; configuration for known patterns; reviewed code for genuinely new triggers | T02, T14 |
| B §5.3.3 | Request/Notification statuses, unique keys, bounded retry, Failed/Unknown support views, last redacted errors, counts and replay; no separate Attempt object | T06, T08, T13 |

## 5. Store visibility acceptance matrix

Every row first requires **Contact Web App includes Store AND associated Account Store Flag = true**. The proposed associated Account is the currently selected, server-validated effective Account. If either prerequisite fails, hide the entire Store category. Mandatory groups remain hidden even if all other criteria match. All values below are business labels, not verified Salesforce field API names.

| Group | Region | Additional conditions | Expected visibility |
| --- | --- | --- | --- |
| Approval Status | North America | Role in Customer Lead / Customer Manager AND Account Assigned Features includes `24HG` | Show optional group only if all conditions pass |
| Approval Status | EMEA | Account Type = Customer AND Role in Customer Manager / Customer User AND Contact Approval Process Required = true | Show optional group only if all conditions pass |
| Billing | North America | No additional role restriction | Show optional group |
| Order Status | North America | No additional role restriction | Show optional group |
| Billing / Order Status | EMEA | Irrespective of role | Hide |
| Any Store group | Other / unknown region | No approved matrix supplied | Hide pending mapping; do not infer email suppression |

These are **settings visibility** rules. They must not be copied into existing delivery flows as new email filters. Nor does hiding an optional setting silently erase its saved preference. Existing email producers need individual mapping and approval before integration with the new preference service.

## 6. Information needed before build commitments

| Priority | Missing input / evidence | Responsible owner | Consequence |
| --- | --- | --- | --- |
| P0 | External-user license/data access, actual header integration and custom inbox vertical slice | Salesforce architect | Validate secure object-backed publication, display-time translation and state handling |
| P0 | Inbox retention, expiry/withdrawal policy, cleanup grace period and expected storage | Product / operations | Custom object lifecycle is application-owned; 30 days is proposed, not inherited from native notifications |
| P0 | Real field/object mappings for Web App, Store Flag, Assigned Features, role, region, language, Location and delegation | Nimbus data/access owners | Cannot implement or certify recipient eligibility using guessed fields |
| P0 | Completed existing NA/EMEA notification inventory and approved grouping/channel mapping | Store Product Owner + email owners | S7 FR17 blocks release of corresponding controls |
| P0 | Active users per store, events/day, recipients/event, peak fan-out, email/day, existing shared limits | Platform owner | Determines native email feasibility and worker sizing |
| P0 | Default optional preferences, mandatory communication policy, cross-store scope, effective Account interpretation | Product Owner | Required for predictable first-use behavior |
| P1 | Supported site locales, Contact language mapping, translation ownership and completeness rules | Localization owner | Required for activation and language acceptance tests |
| P1 | Source event schemas, event IDs, subject record visibility, replay horizon and stale-event policy | Application owners | Determines trigger adapters and recovery guarantees |
| P1 | Measurable delivery/freshness targets, operational-log retention and support ownership | Product / operations | Proposed service targets are not contractual SLAs |
| P1 | Manual send audience preview, authorization, approval and cancellation requirements | Product Owner | Avoids an unestimated campaign-authoring feature |

## 7. Recommended delivery order

1. Build a custom-object/LWR vertical slice for publication, dynamic translation, read state and authorization; complete field/email mappings and retention sizing.
2. Implement the six-object schema, versioned Definition records, shared Translation records, preferences and exact Store settings visibility.
3. Implement durable ingress, audience resolver, Bell/Email adapters, retries and diagnostics with representative automatic notifications.
4. Migrate existing emails incrementally, verify no duplicate producer, and run performance/security/UAT gates.
5. Add approved connected sources and, if requested, manual send tooling using the same service.

The updated design adopts the user-confirmed custom inbox architecture with six custom data objects. The earlier native translation feasibility question is resolved by that choice. Implementation estimates still depend on the actual entitlement mappings, event inventory, external-user access and storage/email volumes.

## 8. Object-count review and accepted design trade-offs

| Object | Why it remains separate |
| --- | --- |
| Group | Owns customer-facing topic and Optional/Mandatory policy shared by definitions |
| Definition | Owns business trigger, channel and targeting configuration; versions use this same object |
| Translation | Enables admin-managed locale content without duplicating translations per recipient; also stores Group labels |
| Preference | Relates Contact to Group with independent Bell/Email choices across Accounts/Locations |
| Request | Persists a source event before recipients exist and carries expansion/recovery state |
| Notification | One recipient/event/store row for Bell inbox state and both channels' delivery outcomes |

No separate Revision, Store junction, Audience Value, Audience Work, Delivery or Attempt object is included. Controlled targeting fields suit the supplied small vocabularies; a large segment-management system is not assumed. Attempt counts and the latest failure satisfy basic supportability, but do not provide an immutable attempt timeline. Expansion is sequential in bounded chunks per Request, with concurrency across Requests. Bell expiry cannot delete a recipient row while Email processing remains pending or unresolved. These boundaries are covered in the revised technical design and test plan.
