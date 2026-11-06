# Spec Delta

## Purpose

Lets a fund manager attach several rule packs to each fund with a classification per pack, map pack inputs and reference lists once, override or disable checks under maker–checker approval, assign compliance roles, and see the full history of setup changes.

## ADDED Requirements

### Requirement: Attach several packs to a fund
A compliance editor SHALL be able to attach any published pack to any fund they can access, with a classification from that pack's list. A fund MAY carry any number of different packs but the same pack at most once. The SEBI pack SHALL pre-fill the classification from the fund's Category when it matches. Changing a fund's classification in an attached pack SHALL be a setup change approved like an override and SHALL apply from approval. The entity's regulator setting SHALL only order the suggestions.

#### Scenario: Two packs on two funds
- **WHEN** Meera attaches SEBI (Category II) to Growth Fund I and IFSCA (Restricted Scheme) to GIFT Opportunities, and the fund-agreement pack to both
- **THEN** the setup grid shows SEBI · Category II and FA on Growth Fund I, IFSCA · Restricted and FA on GIFT Opportunities

#### Scenario: Same pack twice refused
- **WHEN** Meera attaches SEBI to Growth Fund I a second time
- **THEN** it is refused with "SEBI — AIF is already attached to this fund"

#### Scenario: Category pre-fills SEBI classification
- **WHEN** a fund with Category "Category II" gets the SEBI pack
- **THEN** the classification is pre-filled Category II and can be changed

#### Scenario: Classification change needs approval
- **WHEN** Meera changes Growth Fund I from Category II to Category II — LVF and Rahul approves on 12 Nov
- **THEN** runs up to 12 Nov use 25% and the 13 Nov run uses 50%; before approval the change shows "Pending approval"

#### Scenario: Non-SEBI regulator setting does not block
- **WHEN** an entity whose regulator setting is SEBI attaches the IFSCA pack to a fund
- **THEN** the attachment is allowed

### Requirement: Unclassified and unmonitored funds are visible
An attachment without a classification SHALL show "<Pack>: no classification — no checks run" and appear in the digest daily until fixed. A fund with no pack SHALL be listed under "Not monitored".

#### Scenario: Attachment without classification
- **WHEN** Horizon Seed Fund carries SEBI with no classification
- **THEN** its dashboard shows "SEBI — AIF: no classification — no checks run" in amber and no SEBI check runs

#### Scenario: Fund with no pack
- **WHEN** a fund has no pack attached
- **THEN** it is listed under "Not monitored" on the Compliance home page

### Requirement: Input mapping
Setup SHALL list every input needed by packs attached to the entity's funds with ✓/✗ and the checks each missing input blocks. An input used by several packs SHALL be mapped once per entity. Monitoring MUST NOT be turned on while a required input is missing; the button SHALL name the missing input.

#### Scenario: Shared input mapped once
- **WHEN** Meera maps "Sponsor/manager" to category "Sponsor"
- **THEN** both the SEBI and IFSCA packs use that mapping

#### Scenario: Monitoring blocked by missing input
- **WHEN** estimated expenses are missing for Horizon Seed Fund
- **THEN** Turn monitoring on is disabled with "1 input missing — Estimated expenses"

### Requirement: Reference lists
Setup SHALL hold reference lists used by checks: IC members and quorum, sponsor's associates, excluded sectors. Each entry MAY have a from and a to date (both inclusive; blank = always). A list used by a check MUST have at least one entry; the IC quorum MUST NOT exceed the number of IC members.

#### Scenario: Dated list entry saved
- **WHEN** Meera records R. Mehta as an IC member from 01 Apr 2025 to 15 Oct 2026
- **THEN** the entry is saved with both dates

#### Scenario: Quorum above members refused
- **WHEN** Meera enters 5 IC members and a quorum of 6
- **THEN** it is refused with "Quorum cannot exceed 5 members"

### Requirement: Overrides with maker–checker approval
An override SHALL change one check's limit on one fund, require a reason of at least 10 characters, and take effect only when approved by a compliance approver or company admin other than the requester. If the entity has exactly one user eligible to approve, that user MAY self-approve, and the approval SHALL be labelled "Self-approved — single approver" on the item, in history and in exports. On a locked pack an override MUST be stricter than the pack's limit: a looser or equal limit, or any override on a check marked "not overridable", MUST be refused. Until approved the pack's limit SHALL apply and the override SHALL show "Pending approval". A rejected override SHALL be discarded and the requester notified. Results SHALL show the pack's value beside an approved override.

#### Scenario: Override pending
- **WHEN** Meera requests concentration 25% → 20% on Growth Fund I with reason "Board policy 2026-07"
- **THEN** runs keep using 25% and the check shows "Override pending approval"

#### Scenario: Override approved
- **WHEN** Rahul approves the override
- **THEN** the next run uses 20% and shows "20% (pack: 25%)"

#### Scenario: Self-approval refused
- **WHEN** Meera, who requested the override, tries to approve it, including by a direct request
- **THEN** the approval is refused with "Another approver must approve your request"

#### Scenario: Company admin approves
- **WHEN** Meera requests an override and Anil, a company admin without the approver role, approves
- **THEN** the override takes effect

#### Scenario: Single eligible user self-approves
- **WHEN** an entity's only compliance approver and company admin is Meera and she requests and approves an override
- **THEN** it takes effect, labelled "Self-approved — single approver" on the item, in history and in exports

#### Scenario: Override rejected
- **WHEN** Rahul rejects the override
- **THEN** it is discarded and Meera is notified

#### Scenario: Short reason refused
- **WHEN** an override reason has fewer than 10 characters
- **THEN** it is refused with "Give a reason (at least 10 characters)"

#### Scenario: Looser override refused on a locked pack
- **WHEN** Meera requests concentration 25% → 30% on Growth Fund I
- **THEN** it is refused with "Locked pack: overrides can only tighten this limit"

#### Scenario: Override equal to the pack limit refused
- **WHEN** Meera requests concentration 25% → 25%
- **THEN** it is refused with "Same as the pack's limit"

#### Scenario: Override on a not-overridable check refused
- **WHEN** Meera requests an override of "Investors in scheme", marked not overridable, including by a direct request
- **THEN** the request is refused

### Requirement: Overrides across pack versions
When a new version takes effect for a fund, an override on a check whose identity is unchanged SHALL be kept if it is stricter than or equal to the new limit; if the new limit is stricter than the override, the override SHALL be dropped, the new limit SHALL apply and the drop SHALL be flagged; overrides on removed checks SHALL be archived. Every such change SHALL appear in Setup › History and the next digest.

#### Scenario: Override kept when still stricter
- **WHEN** Growth Fund I has a 20% override and v2 changes the limit to 22%
- **THEN** the 20% override is kept

#### Scenario: Override kept when equal to the new limit
- **WHEN** Growth Fund I has a 20% override and v2 changes the limit to 20%
- **THEN** the override is kept

#### Scenario: Override dropped when the new limit is stricter
- **WHEN** Growth Fund I has a 20% override and v2 changes the limit to 18%
- **THEN** the override is dropped, 18% applies, and History and the digest say "Override 20% dropped — v2 limit 18% is stricter"

#### Scenario: Override archived when its check is removed
- **WHEN** v2 removes a check that had an override on Growth Fund I
- **THEN** the override is archived and shown in History

### Requirement: Early adoption of a published version
If a published version allows early adoption, a compliance editor SHALL be able to request it for a fund and a compliance approver other than the requester SHALL approve it; the fund then moves to the new version from the next run, before the effective date, and the move MUST NOT be undone. If the version does not allow early adoption the request MUST be refused. There SHALL be no manual pinning of a fund to an older version and no switching back.

#### Scenario: Early adoption approved
- **WHEN** SEBI v2 (effective 01 Jan 2027) allows early adoption and Meera requests it for Growth Fund I on 10 Dec and Rahul approves
- **THEN** the 11 Dec run of Growth Fund I records v2 and other funds stay on v1 until 01 Jan

#### Scenario: Early adoption not allowed
- **WHEN** v2 does not allow early adoption and Meera requests it
- **THEN** the request is refused with "This version does not allow early adoption"

#### Scenario: Early adoption self-approval refused
- **WHEN** Meera requests early adoption and then approves it herself, including by a direct request
- **THEN** the approval is refused

#### Scenario: Early adoption cannot be undone
- **WHEN** Growth Fund I has adopted v2 early and a request to move it back to v1 is sent
- **THEN** the request is refused

#### Scenario: Pinning to an older version refused
- **WHEN** a request pins a fund to SEBI v1 after v2 is effective for it
- **THEN** the request is refused

### Requirement: Disable a check and detach a pack under approval
Disabling a check on a fund and detaching a pack from a fund SHALL each require a reason and approval by a different compliance approver. A disabled check SHALL show "Disabled by <requester>, approved by <approver> on <date>". After an approved detach, open items for that pack SHALL close as "Pack detached" and its history SHALL remain viewable read-only.

#### Scenario: Disable approved
- **WHEN** Meera requests disabling "Investors in scheme" on a fund and Rahul approves
- **THEN** the check stops running and the register shows the disabled line

#### Scenario: Detach approved
- **WHEN** a detach of the SEBI pack from a fund is approved
- **THEN** open SEBI items on that fund close as "Pack detached" and SEBI history stays viewable

### Requirement: Compliance roles
The system SHALL provide compliance viewer, editor and approver roles per entity, limited to funds the user can already access. Company admins SHALL hold all three by default. Viewers see dashboards, register and history; editors also change setup, assign, explain, upload, mark signed, confirm facts and mark duties done; approvers also approve explanations, overrides, disabling and detaching.

#### Scenario: Viewer cannot change setup
- **WHEN** a compliance viewer requests an attachment change directly
- **THEN** it is refused

#### Scenario: Fund access limits compliance access
- **WHEN** an editor without access to GIFT Opportunities opens Compliance
- **THEN** GIFT Opportunities and its register items are not shown and direct requests are refused

### Requirement: Tenant isolation and no investor access
Compliance setup, results, register, history and exports MUST be scoped to the user's entity. Users of another firm, investors and investor advisors MUST NOT see or change any of it, including by direct requests.

#### Scenario: Other firm refused
- **WHEN** a user of another firm requests Horizon's register item or setup page directly
- **THEN** the request is refused

#### Scenario: Investor refused
- **WHEN** an investor or investor advisor of Growth Fund I requests any Compliance page
- **THEN** the request is refused and Compliance does not appear in their menus

#### Scenario: Firm without Compliance
- **WHEN** Horizon's Compliance flag (the existing enable_compliance entity setting) is off
- **THEN** no user of Horizon sees the Compliance menu, Compliance pages or the fund-page Compliance tab, and no nightly run, digest or document reading happens for Horizon

#### Scenario: Staff with an investor role
- **WHEN** Meera, a company admin who also holds the investor role, opens Compliance while acting as an employee
- **THEN** the page shows; and once she switches to her investor role, the same request is refused

### Requirement: Setup history
Every setup change (attachments, classifications, mappings, reference lists, overrides, disabling, detaching, roles, owners, fact edits) SHALL be recorded with who, when, before → after and the approver where applicable, in Setup › History. Input-mapping and reference-list changes SHALL apply from the change; past results MUST NOT be rewritten. Each result SHALL link to the setup that applied to its run.

#### Scenario: Mapping change applies from the change
- **WHEN** Meera remaps "Sponsor/manager" on 12 Nov
- **THEN** the 11 Nov result keeps its figures and the 13 Nov run uses the new mapping

#### Scenario: Result shows the setup of its day
- **WHEN** an override was approved on 10 Nov and Meera opens the 9 Nov result
- **THEN** the result's setup view shows the pack limit without the override

### Requirement: Owners and turning monitoring on
Setup SHALL name the compliance owner(s) who receive the digest and own manual duties; a duty with no named owner SHALL default to the compliance owner. Turning monitoring on SHALL schedule nightly runs and create the first due dates for every attached pack's duties. Turning Compliance off SHALL stop runs and make history read-only; turning it on again SHALL resume from that date with no backfilled runs or duties.

#### Scenario: Compliance turned off and on
- **WHEN** Horizon turns Compliance off on 01 Dec and on again on 10 Dec
- **THEN** no runs exist for 02–10 Dec before 02:00 on 11 Dec, history stays read-only meanwhile, and no duties are backfilled

#### Scenario: Monitoring on
- **WHEN** Meera names herself owner and turns monitoring on
- **THEN** the screen says "Monitoring on — first run tonight" and the quarterly SEBI report duty gets its first due date
