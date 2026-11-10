# kyc/bank-detail-change-controls Specification

## Purpose
Protects an investor's payout account: a change to a KYC's account number, IFSC or a custom field its firm
has marked as a payout field (such as SWIFT or IBAN) clears its bank verification at once, is recorded, is emailed to the investor and the firm's approvers, and must be verified
by a second person before it counts as confirmed.

## Requirements

### Requirement: What counts as a bank change
The KYC's account number and IFSC (routing code), together with every custom field its firm has marked as a
payout field on that KYC's form, SHALL be its bank details. A save of an existing KYC SHALL be a bank change
when any of them changes from a non-blank value to a different value, comparing values with spaces removed
and letters upper-cased. Entering bank details where none existed (first fill) SHALL NOT
be a bank change. Changing only the bank name, branch or account type SHALL NOT be a bank change.

#### Scenario: Account number changed
- **WHEN** a fund user changes a KYC's account number from 50100012344821 to 50100273107310 and saves
- **THEN** the save is recorded as a bank change from account ending 4821 to account ending 7310

#### Scenario: First fill is not a change
- **WHEN** an investor enters an account number on a KYC whose account number was blank
- **THEN** no bank change is recorded and no change email is sent

#### Scenario: Same value re-typed
- **WHEN** a user re-saves the IFSC "icic0004567 " over "ICIC0004567"
- **THEN** no bank change is recorded

#### Scenario: Branch name only
- **WHEN** a user changes only the branch name from "MG Road" to "Indiranagar"
- **THEN** no bank change is recorded and Bank Verified is unchanged

### Requirement: Payout custom fields
A firm SHALL be able to mark a text custom field on its KYC forms as a payout field, as either a bank code
(shown in full, like the IFSC — for example SWIFT/BIC, ABA routing number, sort code) or an account identifier
(shown as its last 4 characters only, like the account number — for example IBAN). The mark SHALL be stored on
the field's definition and be set where custom fields are edited today: the custom fields side panel on a
record page and Form Types › Edit, and editing the field's other settings (label, help text, input rules) SHALL
keep it. A change to a marked field SHALL follow every rule a change to the account
number follows: Bank Verified clears, a verified KYC is unverified, the change is recorded, the investor and
the approvers are emailed, a second person verifies (with the only-approver exception), imports leave the KYC
unverified with a warning, and payouts flag it. A change to an unmarked custom field SHALL NOT be a bank
change. A mark SHALL apply only to the form it was set on. Marking a field SHALL NOT change any existing KYC,
send any email or record any earlier change; the rules apply to saves made after the mark.

#### Scenario: Firm marks a payout field
- **WHEN** Ravi Iyer (company admin) marks "SWIFT Code" as a bank code and "IBAN" as an account identifier on Horizon Capital's Individual KYC form
- **THEN** both fields show as payout fields in the side panel and in Form Types › Edit, and no KYC changes

#### Scenario: Marked field change is a bank change
- **WHEN** Meera Shah changes Farah Ali's SWIFT Code from EBILAEADXXX to NBADAEAAXXX after "SWIFT Code" was marked
- **THEN** Bank Verified is off and the KYC page shows "Bank details changed on 09/11/2026 by Meera Shah — SWIFT Code EBILAEADXXX → NBADAEAAXXX. Waiting for a second approver to verify."

#### Scenario: Marked SWIFT change on a verified KYC
- **WHEN** an "Update Only" import row with Verified = Yes changes the marked SWIFT Code of a verified KYC
- **THEN** the row reports "Bank details changed — the KYC was left unverified for another approver to verify" and the KYC awaits a second person

#### Scenario: Marked field shown masked in emails
- **WHEN** Meera Shah changes Farah Ali's marked IBAN from one ending 3456 to one ending 8901
- **THEN** farah.ali@example.ae receives "Your bank details with Horizon Capital were changed" showing "IBAN ending 3456 → ending 8901" and no full IBAN

#### Scenario: Unmarked custom field change ignored
- **WHEN** Meera Shah changes the unmarked "Intermediary Bank Name" field
- **THEN** Bank Verified is unchanged, no bank change is recorded and no change email is sent

#### Scenario: Marking does not change existing KYCs
- **WHEN** Ravi Iyer marks "SWIFT Code" on a form whose KYCs are already verified with Bank Verified on
- **THEN** every KYC keeps its Verified and Bank Verified values and no email is sent

### Requirement: Who may mark payout fields
Marking a field as a payout field SHALL be allowed to whoever may edit the firm's form types (a company admin
of the firm) and to CapHive support. Removing the mark, or deleting a marked field, SHALL be allowed only to
CapHive support, and anyone else's attempt SHALL be refused with "Payout fields can only be unmarked by
CapHive support." Only text fields on KYC forms SHALL be markable; any other field SHALL be refused with "Only
text fields on a KYC form can be payout fields". A support rollout task SHALL propose the existing SWIFT, BIC,
IBAN, routing, sort code and ABA text fields of a firm without changing anything unless it is run with
EXECUTE=1.

#### Scenario: Only support unmarks a payout field
- **WHEN** Ravi Iyer (company admin) removes the payout mark from "IBAN"
- **THEN** the save is refused with "Payout fields can only be unmarked by CapHive support." and "IBAN" stays marked

#### Scenario: Only text fields on KYC forms can be marked
- **WHEN** a payout mark is sent for the check box "Foreign account?"
- **THEN** it is refused with "Only text fields on a KYC form can be payout fields"

#### Scenario: Rollout proposal marks nothing without EXECUTE
- **WHEN** CapHive support runs the payout field proposal for a firm without EXECUTE=1
- **THEN** it lists the firm's SWIFT and IBAN text fields with the proposed kind and changes nothing

### Requirement: Bank Verified clears in the same save
A save that changes the account number, the IFSC or a marked payout field (bank change or not) SHALL set Bank Verified off and clear the
stored bank check status and response in that same save, whatever value of Bank Verified was sent with it,
on every way a KYC is saved: the KYC form, the JSON API, imports, Document Checks and AI document
extraction. The previous values SHALL remain in the KYC's audit trail. When the firm has bank verification
off, the Bank Verified badge SHALL read "Not verified — bank details changed".

#### Scenario: Cleared immediately with checks off
- **WHEN** a firm with bank verification off changes a Bank Verified KYC's account number
- **THEN** the KYC page shows "Not verified — bank details changed" straight after the save

#### Scenario: Cleared even if the form sent the tick
- **WHEN** the edit form is saved with a new account number and the Bank Verified box still ticked
- **THEN** Bank Verified is off after the save

#### Scenario: Cleared on a Document Checks fill-in
- **WHEN** Document Checks writes a new account number from a cancelled cheque into a KYC
- **THEN** Bank Verified is off and the bank change is recorded

### Requirement: A verified KYC is unverified by a bank change
When a bank change is saved on a verified KYC, the same save SHALL set the KYC to submitted-but-unverified,
exactly as UnVerify does, and its journey SHALL move back with the note "Bank details changed".

#### Scenario: Import changes a verified KYC
- **WHEN** an "Update Only" import row changes the IFSC of a verified KYC
- **THEN** the KYC is no longer verified and its journey shows the Verify task as current

### Requirement: Bank change record
Every bank change SHALL be kept as a record showing who made it (a firm user, an investor, or "System" for
background work with no user), how it was made (screen or API, import, Document Checks, AI extraction), when,
the last 4 digits of the old and new account numbers, the old and new IFSC, each changed payout custom field
by its label (in full when the firm marked it as a bank code, last 4 characters only when marked as an
account identifier), and its state: awaiting a second
person, confirmed (by whom, when, and whether as the only approver), or replaced by a later change. Full
account numbers SHALL NOT be stored in it. Fund users who can see the KYC SHALL see the latest record on the
KYC page; investors SHALL NOT see it.

#### Scenario: Note on the KYC page
- **WHEN** Meera Shah changes the account and Ravi Iyer opens the KYC
- **THEN** the Contact & Banking card shows "Bank details changed on 09/11/2026 by Meera Shah — account ending 4821 → 7310. Waiting for a second approver to verify."

#### Scenario: Later change replaces an awaiting one
- **WHEN** an awaiting change is followed by another bank change before anyone verifies
- **THEN** the first record is marked replaced and only the new one awaits a second person

#### Scenario: Investor does not see the note
- **WHEN** Anil Kumar opens his own KYC after a bank change
- **THEN** no change note is shown to him

### Requirement: Second person verifies
While a bank change awaits a second person, its maker SHALL NOT be able to verify the KYC by any route: the
Verify button (shown greyed out with the tooltip "You changed this KYC's bank details. Another KYC approver
must verify it."), a direct request or API call (refused with "You changed this KYC's bank details, so
another KYC approver must verify it."), bulk Verify (skipped and listed as "Not verified — you changed the
bank details; another approver must verify") or an import row with Verified = Yes. Any other KYC approver
SHALL be able to verify, and doing so SHALL mark the change confirmed by that approver. A change whose maker
is an investor or "System" SHALL be confirmed by any KYC approver's Verify. UnVerify SHALL stay available to
the maker.

#### Scenario: Maker's Verify is greyed out
- **WHEN** Meera Shah opens a KYC whose bank details she changed
- **THEN** Verify is greyed out with "You changed this KYC's bank details. Another KYC approver must verify it."

#### Scenario: Maker's direct request refused
- **WHEN** Meera Shah sends the Verify request for that KYC directly
- **THEN** it is refused with "You changed this KYC's bank details, so another KYC approver must verify it." and the KYC stays unverified

#### Scenario: Maker's bulk Verify skips the KYC
- **WHEN** Meera Shah bulk-verifies three KYCs, one of which has her awaiting bank change
- **THEN** two are verified and the third is listed as "Not verified — you changed the bank details; another approver must verify"

#### Scenario: Second approver verifies
- **WHEN** Ravi Iyer clicks Verify and confirms the popup
- **THEN** the KYC is verified and the note reads "Confirmed by Ravi Iyer on 10/11/2026"

#### Scenario: Investor-made change
- **WHEN** Anil Kumar changes his account through the KYC form and Meera Shah verifies
- **THEN** the KYC is verified and the change is confirmed by Meera Shah

#### Scenario: Maker can still unverify
- **WHEN** Meera Shah unverifies a verified KYC she later changes
- **THEN** UnVerify works as today

### Requirement: Verify popup when a change awaits
When a KYC approver who may confirm clicks Verify on a KYC with an awaiting bank change, a confirmation popup
SHALL list, as action cards, the new payout account (last 4 digits and IFSC), the maker and date, whether
and to whom the investor email was sent, and, when the bank check has not passed, its status. Verifying
SHALL happen only after the popup is confirmed. With no awaiting change, Verify SHALL behave as today.

#### Scenario: Popup cards
- **WHEN** Ravi Iyer clicks Verify on Anil Kumar's KYC with an awaiting change
- **THEN** the popup shows "New payout account confirmed", "You are the second person", "Investor already told" and a Verify KYC button

#### Scenario: No change, no popup
- **WHEN** Ravi Iyer clicks Verify on a KYC with no awaiting change
- **THEN** the KYC is verified directly, as today

### Requirement: Only-approver exception
When the firm has no active KYC approver other than the maker, the maker SHALL be able to verify after the
popup shows "You are the only KYC approver at <firm> — this is recorded as confirmed by the person who made
the change.", and the change SHALL be recorded as confirmed by the only approver.

#### Scenario: One-approver firm
- **WHEN** Kiran Rao, Solo Advisors' only KYC approver, changes an account and clicks Verify
- **THEN** the popup shows the only-approver card and confirming verifies the KYC, recorded as "Only approver"

#### Scenario: A second approver is added later
- **WHEN** Solo Advisors adds a second KYC approver before Kiran Rao verifies
- **THEN** Kiran Rao's Verify is greyed out like any other maker

### Requirement: Investor change email
Each bank change SHALL email, once, the investor's approved contacts subscribed to KYC emails (or to all
topics) whose access existed before the change, subject "Your bank details with <firm> were changed", showing
who made the change, the date as `Nov 09, 2026`, the last 4 digits of the old and new accounts and both
IFSCs, each changed payout custom field shown the same way as on the change record, and a link to the KYC. It SHALL NOT be sent to any address held in the KYC itself or to a contact added
after the change. A firm SHALL be able to reword it with a custom notification but SHALL NOT be able to turn
it off. It SHALL be sent when the investor made the change too.

#### Scenario: Investor emailed with masked account
- **WHEN** Meera Shah changes Anil Kumar's account
- **THEN** anil.kumar@example.in receives "Your bank details with Horizon Capital were changed" showing "ending 4821 → ending 7310" and no full account number

#### Scenario: Contact added after the change is not emailed
- **WHEN** a new contact is added to Anil Kumar's investor after the bank change
- **THEN** that contact does not receive the change email

#### Scenario: eSign email in the KYC is not used
- **WHEN** the same save changes the account and sets eSign emails to attacker@example.com
- **THEN** attacker@example.com receives no change email

#### Scenario: Sent once on retry
- **WHEN** the email job runs twice for the same change
- **THEN** each contact receives the email once

### Requirement: Approver change email
Each bank change SHALL email and notify in-app, once, the firm's KYC approvers who can see the KYC, except the
maker, subject "Bank details changed for <KYC name> — a second approver must verify", saying whether the
investor email was sent and to whom, or "No investor contact could be emailed — confirm the change with the
investor by phone." when none could be.

#### Scenario: Approvers told, maker not
- **WHEN** Meera Shah changes Anil Kumar's account
- **THEN** Ravi Iyer receives the approver email and Meera Shah does not

#### Scenario: No investor contact
- **WHEN** the investor has no approved contact for KYC emails
- **THEN** the approver email says "No investor contact could be emailed — confirm the change with the investor by phone."

### Requirement: Bank check name rule
For firms with bank verification on, a bank check that finds the account SHALL mark Bank Verified when the
provider reports a name match, or when every word of the bank's name matches a word of the KYC name (or a
single-letter initial matches a word's first letter), or the reverse, with at least one full word in common,
ignoring titles (Mr, Mrs, Ms, Dr, Shri, Smt, M/S), punctuation and company-suffix spellings (Private/Pvt,
Limited/Ltd). Otherwise it SHALL leave Bank Verified off with "Name needs review: the bank has '<bank name>'".
A failed check SHALL keep the provider's error as today. The check's result SHALL be applied only if the
account number and IFSC are still the ones it checked.

#### Scenario: Look-alike name goes to review
- **WHEN** the bank returns "R KUMAR" for KYC "A Kumar"
- **THEN** Bank Verified stays off with "Name needs review: the bank has 'R KUMAR'"

#### Scenario: Initial accepted
- **WHEN** the bank returns "THIMMAIAH C" for KYC "Thimmaiah Chengappa"
- **THEN** Bank Verified is on

#### Scenario: Company suffixes
- **WHEN** the bank returns "ABC PVT LTD" for KYC "ABC Private Limited"
- **THEN** Bank Verified is on

#### Scenario: Stale result discarded
- **WHEN** the account changes again while a check of the earlier account is running
- **THEN** the earlier check's result is not applied to the new account

### Requirement: Who may tick Bank Verified and Verified
Bank Verified and Verified sent with a KYC save SHALL be accepted only from a KYC approver of the KYC's firm,
and Bank Verified SHALL NOT be accepted from the maker of an awaiting bank change (unless only-approver
applies). The Bank Verified checkbox SHALL be shown only to users allowed to tick it. Values sent by others
SHALL be ignored without failing the save.

#### Scenario: Update-only employee's tick ignored
- **WHEN** Priya Nair (Investor KYC Update, not Approve) saves a KYC with Bank Verified ticked
- **THEN** the KYC saves and Bank Verified is unchanged

#### Scenario: Second approver ticks after review
- **WHEN** Ravi Iyer ticks Bank Verified on a KYC showing "Name needs review"
- **THEN** Bank Verified is on

### Requirement: Verification results are not accepted from users
The bank and PAN verification status and response SHALL be written only by the verification checks; values
sent by any user, including investors through the KYC form, magic link or API, SHALL be ignored.

#### Scenario: Investor sends a forged response
- **WHEN** an investor submits their KYC with a bank verification status of "Verified" and a forged response
- **THEN** both are ignored and the stored values are unchanged

### Requirement: Imports and bank changes
An import row that creates a KYC SHALL behave as today. An "Update Only" row that makes a bank change SHALL
save the row, leave the KYC unverified even when Verified = Yes, and report "Success with warnings" with "Bank
details changed — the KYC was left unverified for another approver to verify". The importing user SHALL be
the maker.

#### Scenario: Update Only with Verified Yes
- **WHEN** Meera Shah imports an Update Only row with a new account number and Verified = Yes
- **THEN** the row reports the warning and the KYC is unverified, awaiting a second person

#### Scenario: New KYC import unchanged
- **WHEN** a row creates a new KYC with Verified = Yes
- **THEN** the KYC is verified as today and no bank change is recorded

### Requirement: Payout flags for unconfirmed changes
Wherever a distribution is paid, a KYC with a bank change awaiting a second person SHALL be flagged: the
distribution readiness check's bank step SHALL fail with "<n> investor(s) have bank details changed and not
yet confirmed. Ask a second approver to verify the KYC before releasing payment.", and the distribution
payments download SHALL carry a last column "Unconfirmed Bank Change" holding the change date, blank when
there is none. Existing columns SHALL keep their order.

#### Scenario: Readiness check flags it
- **WHEN** the readiness check runs on a distribution paying Anil Kumar while his change awaits
- **THEN** the bank step fails with "1 investor(s) have bank details changed and not yet confirmed. Ask a second approver to verify the KYC before releasing payment."

#### Scenario: Download column
- **WHEN** Meera Shah downloads the distribution's payments
- **THEN** Anil Kumar's row shows 09/11/2026 under "Unconfirmed Bank Change" and other rows are blank

### Requirement: KYC journey warning
A KYC with a journey and an awaiting bank change SHALL show the readiness warning "Bank details changed on
<date> by <maker> — a different approver must verify" until the KYC is verified.

#### Scenario: Journey warning shown
- **WHEN** Ravi Iyer opens a journey KYC with an awaiting change made by Meera Shah
- **THEN** the panel warns "Bank details changed on 09/11/2026 by Meera Shah — a different approver must verify"

### Requirement: Existing data and other firms unchanged
At release no KYC's verification, Bank Verified flag or bank details SHALL change, and no email SHALL be sent;
the rules apply only to saves made after release. Bank change records and notes SHALL be visible only to the
KYC's own firm users who can see the KYC.

#### Scenario: Verified KYCs untouched at release
- **WHEN** the change is deployed
- **THEN** every KYC keeps its Verified and Bank Verified values and no email is sent

#### Scenario: Other firm refused
- **WHEN** a Northwind Partners user requests Horizon Capital's KYC page or its Verify action
- **THEN** the request is refused and no change detail is shown
