# Spec Delta

## Purpose

Lets a fund firm require that capital calls and capital distributions are approved by a different person from the
one who prepared them (maker–checker), without blocking firms that rely on one person approving.

## ADDED Requirements

### Requirement: Firm-level maker–checker setting
Each firm SHALL have a maker–checker setting for capital calls and distributions. It SHALL be off for every firm
when this capability is released and for every firm created afterwards. Only a company admin of the firm SHALL be
able to change it. Every change SHALL be recorded with who changed it, when, and the old and new value.

#### Scenario: Off by default
- **WHEN** the capability is released, or a new firm is created afterwards
- **THEN** the firm has the setting off and approving works exactly as before

#### Scenario: Company admin switches it on
- **WHEN** a company admin ticks "Require a second person to approve capital calls and distributions" and saves
- **THEN** the setting is on and the entity's audit trail records the admin, the time and off → on

#### Scenario: Non-admin cannot change it
- **WHEN** an employee who is not a company admin, or a user of another firm, submits the setting directly
- **THEN** the request is refused and the setting is unchanged

### Requirement: Preparers of a call or distribution
The system SHALL record, for each capital call and capital distribution, every person who prepared it: who created
it, who imported it, and who changed any of its figures — on the record itself, on its existing remittances or
distribution payments, or on its fee lines — including by importing them or by recomputing fees. Figures SHALL be
the money, percentage, close, date and unit-price fields that decide what investors pay or receive. Changes to names,
notes, custom fields, notification switches, payments received and verification SHALL NOT make someone a preparer. A
change with no acting person SHALL record nobody. When a CapHive support person acts as a user, the support person (the
real person) SHALL be recorded, and SHALL be refused approval of that record while acting as any user. A person SHALL be recorded at most once per record. The user recorded as the record's creator in
its audit trail SHALL always count as a preparer, so records created before release are covered.

#### Scenario: Creator is a preparer
- **WHEN** Meera creates a capital call through the form or the API
- **THEN** Meera is a preparer of that call

#### Scenario: Editor of call figures is a preparer
- **WHEN** Anil changes the call's percentage called from 10% to 12%
- **THEN** Anil is a preparer of that call

#### Scenario: Editor of a remittance amount is a preparer
- **WHEN** Anil changes one remittance's call amount from ₹1.2 Cr to ₹1.25 Cr
- **THEN** Anil is a preparer of that call

#### Scenario: Distribution payment editor is a preparer
- **WHEN** Anil changes a distribution payment's income
- **THEN** Anil is a preparer of that distribution

#### Scenario: Importer is a preparer
- **WHEN** Anil uploads an import of calls, or of remittances for an Upload-basis call
- **THEN** Anil is a preparer of each call the import created or changed

#### Scenario: Recompute fees makes a preparer
- **WHEN** Anil clicks Recompute Fees and the fees change
- **THEN** Anil is a preparer of that call

#### Scenario: Non-figure edit does not make a preparer
- **WHEN** Ravi changes only the call's name, notes, custom fields or notification switches, records a payment received, or verifies a remittance
- **THEN** Ravi is not a preparer of that call

#### Scenario: Generating many remittances records the person once
- **WHEN** creating a call generates 3,000 remittances in the background, or the same person edits two remittances
- **THEN** that person is recorded once as a preparer

#### Scenario: No acting person records nobody
- **WHEN** a background change with no acting person changes a remittance amount
- **THEN** nobody is recorded as a preparer

#### Scenario: Support acting as a user
- **WHEN** a CapHive support person acting as Meera creates a call
- **THEN** the support person is a preparer of that call and cannot approve it, even while acting as Ravi

#### Scenario: Legacy record counts its creator
- **WHEN** a call was created before release by Meera, whether or not anyone changed it afterwards
- **THEN** Meera counts as its preparer

### Requirement: Preparer cannot approve when maker–checker is on
When the firm's setting is on, approving a capital call or a capital distribution SHALL be refused to any of its
preparers, on every path (the page, a direct request, the JSON API and bulk approve). An approver who is not a
preparer SHALL approve exactly as before: the Approver role, edit rights on the fund, and the existing approval checks
still apply. When the setting is off, approving SHALL behave exactly as before. Approvals granted before the setting
was switched on SHALL stay valid, Unapprove SHALL be unchanged, and imported records and open-ended fund settlement
records SHALL keep working as before.

#### Scenario: Checker approves a call
- **WHEN** Meera prepared "Q4 2026 Drawdown" and Ravi, an approver who did not prepare it, clicks Approve
- **THEN** the call is approved by Ravi

#### Scenario: Preparer is refused on the page
- **WHEN** Meera, an approver who prepared the call, opens the Actions menu
- **THEN** Approve is shown disabled with "You prepared this call, so another approver must approve it (maker–checker is on)."

#### Scenario: Preparer is refused on a direct request
- **WHEN** Meera sends the approve request directly or through the JSON API
- **THEN** the request is refused (Access Denied / HTTP 403) and the call stays unapproved

#### Scenario: Bulk approve reports own records
- **WHEN** Meera bulk-approves three calls and prepared two of them
- **THEN** the one she did not prepare is approved and the result lists "You prepared <call> — another approver must approve it" for each of the other two

#### Scenario: Distribution follows the same rule
- **WHEN** Meera prepared a distribution and tries to approve it with the setting on
- **THEN** she is refused, and Ravi can approve it

#### Scenario: Setting off keeps self-approval
- **WHEN** the setting is off and Sam approves a call he created
- **THEN** the call is approved by Sam

#### Scenario: Earlier approvals stay valid
- **WHEN** a call was self-approved before the firm switched the setting on
- **THEN** it stays approved, and Unapprove remains available to approvers as before

#### Scenario: Journey says a second approver is needed
- **WHEN** the setting is on and a call's journey is waiting at "Approve call"
- **THEN** the panel says "The call is not approved yet — it needs an approver who did not prepare it"

#### Scenario: Unchanged paths keep working
- **WHEN** the setting is on and an imported distribution's payments are marked completed, or an open-ended fund dealing date creates its settlement records
- **THEN** they work exactly as before

### Requirement: Self-approval is labelled
A capital call or distribution page SHALL list its preparers. When it was approved by one of its preparers (possible
only while the setting is off, or before it was switched on), the page SHALL say so next to the approval.

#### Scenario: Labelled self-approval
- **WHEN** Sam created and approved a call while the setting was off
- **THEN** the call page shows "Yes · by Sam Mehta (also prepared it)"

#### Scenario: Preparers are listed
- **WHEN** Meera created a call and Anil changed a remittance amount
- **THEN** the call page shows "Prepared by: Meera Shah, Anil Rao"

### Requirement: Request approval
When the setting is on, a user who may edit an unapproved capital call or distribution but cannot approve it themselves
(a preparer, or an editor without the Approver role) SHALL be able to request approval. The request SHALL show a confirmation describing what will happen, then notify every checker: an active
user of the firm with the Approver role and edit rights on the fund who is not a preparer. It SHALL NOT notify
investors or users of another firm. With no checker it SHALL send nothing and explain how to fix it. A second request
for the same record within one hour SHALL be refused with the time of the earlier request.

#### Scenario: Approvers are notified
- **WHEN** Meera requests approval of "Q4 2026 Drawdown"
- **THEN** Ravi and Priya each receive an email and an in-app alert "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval" and Meera sees "Approval requested from Ravi Iyer and Priya Nair."

#### Scenario: No one can approve
- **WHEN** Meera requests approval and no other active approver with access to the fund exists
- **THEN** nothing is sent and she sees "No one else can approve this call. Ask a company admin to give the Approver role to a colleague with access to this fund, or turn off maker–checker in Settings."

#### Scenario: Asked twice within an hour
- **WHEN** Meera requests approval at 10:42 and again at 11:05
- **THEN** the second request sends nothing and says "Approvers were already asked at 10:42. You can ask again after 11:42."

#### Scenario: Only for unapproved records with the setting on
- **WHEN** the setting is off, the record is already approved, or the user could approve it themselves
- **THEN** Request approval is not offered and a direct request is refused

#### Scenario: Others are refused
- **WHEN** a user of another firm, an investor, or a user without edit rights sends the request directly
- **THEN** the request is refused and nothing is sent

### Requirement: Figure changes after approval withdraw the approval
When the setting is on and a person changes the figures of an approved capital call or distribution — on the record,
its existing remittances or payments (including deleting one), or its fee lines — the approval SHALL be withdrawn:
the record SHALL become unapproved, the person SHALL become a preparer, the journey SHALL record why, and the active
approvers who can edit the fund and the record's other preparers SHALL be alerted (never the person who made the
change, never investors). Changes without an acting person, non-figure edits, payments
received, verification, and new remittances or payments created for a newly added commitment SHALL NOT withdraw an
approval. Open-ended fund settlement records SHALL be exempt. When the setting is off, figure changes SHALL NOT
withdraw an approval.

#### Scenario: Remittance edited after approval
- **WHEN** the setting is on, Ravi approved the call and Anil then changes a remittance's call amount
- **THEN** the call is no longer approved, Anil is a preparer, and approvers receive "Approval of Q4 2026 Drawdown was withdrawn: Anil Rao changed its figures after approval."

#### Scenario: Payment received keeps the approval
- **WHEN** a payment of ₹1.8 Cr is recorded against an approved call's remittance, or a remittance is verified
- **THEN** the call stays approved

#### Scenario: New commitment keeps the approval
- **WHEN** a new commitment is added to the fund and a remittance is created for it in an approved call
- **THEN** the call stays approved

#### Scenario: Change without an acting person keeps the approval
- **WHEN** a background change with no acting person changes an approved call's remittance amount
- **THEN** the call stays approved and the change is logged

#### Scenario: Open-ended settlements are exempt
- **WHEN** a subscription payment is added to or changed on an open-ended fund's settlement call
- **THEN** the settlement stays approved

#### Scenario: Setting off keeps today's behaviour
- **WHEN** the setting is off and figures of an approved call are changed
- **THEN** the call stays approved

### Requirement: Switching maker–checker off is announced
When a firm's setting is switched from on to off, every other active company admin and approver of the firm SHALL be
emailed and alerted in-app with who switched it off and when. Switching it on, or saving without changing it, SHALL
send nothing.

#### Scenario: Switched off
- **WHEN** Ravi switches the setting off on Nov 19, 2026
- **THEN** Priya and Meera receive "Maker–checker for calls and distributions was turned off by Ravi Iyer on Nov 19, 2026." and Ravi receives nothing

#### Scenario: Switched on or unchanged
- **WHEN** Ravi switches the setting on, or saves the entity form without changing it
- **THEN** nothing is sent
