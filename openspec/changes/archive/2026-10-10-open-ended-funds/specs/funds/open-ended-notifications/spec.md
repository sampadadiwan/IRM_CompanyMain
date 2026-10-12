# Spec Delta

## Purpose

Tells the right people about an evergreen fund at the right time: reminders and updates to investors (customisable per fund), and in-app plus email alerts to the fund's own team when something needs doing. Each notification can be switched on or off per fund, is sent once per record, and a fund can copy its customised investor emails from another evergreen fund.

## ADDED Requirements

### Requirement: Recipients are named roles resolved from existing data
The system SHALL resolve every evergreen notification's recipients from these roles, and SHALL NOT keep a separate recipient list:

| Role | Who | Resolved from |
|---|---|---|
| Investor users | The investor's users who receive the fund's notices today, including the investor's advisors only if they are allowed to see that order | `investor.notification_users(order)` — the order (not the fund) is passed, so each user is checked against `DealingOrderPolicy#show?`. For a notification about a folio rather than an order (units unlocked, NAV update), the folio is passed |
| Approvers | Employees of the fund's entity with the `approver` role | The existing role |
| Relationship manager | The investor's "Managed by" employee | `Investor#managed_by`; when it is empty, Fund ops is used instead |
| Fund ops, Fund accounting, Compliance | Employees who carry the user notification tag "FundOps", "FundAccounting" or "Compliance" | New values in `User::NOTIFICATION_TAGS`, chosen on the user form like "Kpi" and "Tasks" |

Every internal recipient (approver, relationship manager, tagged user) SHALL also be able to see the fund (`FundPolicy#show?`); anyone who cannot SHALL be left out.

#### Scenario: Advisor without access to the order
- **WHEN** B LLP's redemption is acknowledged, and B LLP's access list holds two B LLP users and one advisor user of Vikram Advisors who is not allowed to see that order
- **THEN** only the two B LLP users receive the email, and the advisor receives nothing

#### Scenario: Advisor approved to see the order
- **WHEN** the same Vikram Advisors user is allowed to see B LLP's redemption and the redemption is acknowledged
- **THEN** the advisor receives the email as well

#### Scenario: No relationship manager falls back to Fund ops
- **WHEN** Q Capital, which has no "Managed by" employee, subscribes through the portal
- **THEN** the new-order alert goes to the users tagged "FundOps" (Asha)

#### Scenario: Tagged user who cannot see the fund
- **WHEN** Meera carries the "Compliance" tag but has no access to Alpha Long-Short Fund, and a gate is applied on Alpha
- **THEN** Meera receives no gate-applied alert

### Requirement: Investor notifications
The system SHALL send these emails to investor users. The existing emails SHALL always be sent. The new ones SHALL follow the fund's switches, with the defaults shown. Every investor email SHALL use the fund's "Evergreen" custom notification for that email when one exists, otherwise the built-in wording. Dates SHALL use CapHive's email date format.

| Email | Kind | Sent when | Default |
|---|---|---|---|
| Subscription / redemption acknowledgement, payment instructions, gate notice, request moved, request cancelled, contract note, redemption advice | Existing | As in open-ended-documents. Contract note and redemption advice: when units are allotted / the redemption is paid if the fund has no template of that kind (no PDF), otherwise at Approve and send (PDF attached) | Always on |
| Payment reminder | New, daily check | *N* days before the cut-off (default 2), for each pre-funded subscription not yet fully paid | On |
| Action needed | New, daily check | *N* days before the cut-off, for each order whose journey has an unfinished step; names the step and whether the order will roll or be cancelled | On |
| Payment received | New, event | A subscription payment is recorded and verified | On |
| Units unlocked | New, daily check | On the day a lot's lock-up ends | Off |
| NAV update | New, event | A NAV is approved: NAV per unit and the investor's holding value, one email per folio of that class | Off |

#### Scenario: Payment reminder
- **WHEN** the daily check runs on 26 Oct 2026 for Alpha (cut-off 28 Oct, reminder days 2) and Q Capital's ₹2,50,00,000 pre-funded subscription for 2 Nov is unpaid
- **THEN** Q Capital's users receive "Payment reminder" stating ₹2,50,00,000, "Pay by Oct 28, 2026", the bank details and the reference

#### Scenario: No reminder when paid
- **WHEN** the same check runs and P Family Trust's subscription is fully paid and verified
- **THEN** P Family Trust receives no payment reminder

#### Scenario: Action needed names the step and its fate
- **WHEN** the daily check runs on 26 Oct 2026 and R Trust's subscription for 2 Nov is at "Collect signed subscription form", with unready handling Roll
- **THEN** R Trust's users receive "Action needed" naming "Upload your signed subscription form" and saying that if it is not done by Oct 28, 2026 the request moves to the Dec 01, 2026 dealing date

#### Scenario: Action needed when unready orders are cancelled
- **WHEN** the fund's unready handling is Cancel and the same check runs
- **THEN** the email says the request will be cancelled if the step is not done by Oct 28, 2026

#### Scenario: Payment received
- **WHEN** Asha records and verifies P Family Trust's ₹5,00,00,000 on 23 Oct 2026
- **THEN** P Family Trust's users receive "Payment received" for ₹5,00,00,000 against the 2 Nov 2026 dealing date

#### Scenario: Units unlocked
- **WHEN** Alpha has "Units unlocked" switched on and the daily check runs on 2 Nov 2027, the day P Family Trust's 4,892.3679 units allotted on 2 Nov 2026 leave their 12-month lock-up
- **THEN** P Family Trust's users receive "Units unlocked" stating 4,892.3679 units in folio F-101 are now free to redeem

#### Scenario: NAV update
- **WHEN** Alpha has "NAV update" switched on and Ravi approves the class A NAV for 30 Nov 2026 at ₹10,160.94
- **THEN** P Family Trust's users receive one email for folio F-101 stating NAV per unit ₹10,160.94 as of Nov 30, 2026 and a holding value of ₹4,97,11,057 (4,892.3679 units)

#### Scenario: Customised wording
- **WHEN** Alpha has an "Evergreen" custom notification for the payment reminder with subject "Reminder: fund your {{fund_name}} subscription"
- **THEN** the payment reminder is sent with that subject and body, with placeholders filled in

### Requirement: Internal notifications
The system SHALL send these alerts to the fund's team, both in-app and by email, with fixed wording that is not customisable. Each SHALL follow the fund's switches, with the defaults shown.

| Alert | Sent when | Recipients | Default |
|---|---|---|---|
| New order | An investor places an order in the portal | Relationship manager, else Fund ops | On |
| NAV awaiting approval | A NAV is drafted or uploaded | Approvers, never the NAV's preparer | On |
| NAV approved | A NAV is approved | The preparer and Fund ops | On |
| Cut-off summary | Daily check, the day after a cut-off | Fund ops | On |
| Ready to confirm | A dealing date's NAV is approved and its cut-off has passed | Fund ops and approvers | On |
| Gate applied | A dealing date is confirmed with an amount carried forward | Compliance and Fund ops | On |
| Large redemption | A redemption is placed for at least *X* % of its class's latest approved NAV (default 2 %) | Compliance and the relationship manager | On |
| Settlement overdue | Daily check: redemption payments unpaid after their due date; pay-after-dealing subscription money not in after its pay-by date | Fund ops | On |
| Fee accrual behind | A NAV is drafted while the management fee is accrued only to an earlier date | Fund accounting | On |
| Documents awaiting approval | Generate documents finishes having generated at least one contract note or redemption advice (only funds with a template) | Approvers | On |

#### Scenario: New order goes to the relationship manager
- **WHEN** P Family Trust, managed by Karan, subscribes ₹5,00,00,000 through the portal on 20 Oct 2026
- **THEN** Karan receives "New subscription: P Family Trust ₹5,00,00,000 for 2 Nov 2026" in-app and by email, and Fund ops do not

#### Scenario: NAV awaiting approval skips the preparer
- **WHEN** Asha, who also has the approver role, drafts the class A NAV for 31 Oct 2026, and Ravi is the other approver
- **THEN** Ravi receives "NAV awaiting approval: Class A, Oct 31, 2026" and Asha does not

#### Scenario: NAV approved
- **WHEN** Ravi approves that NAV
- **THEN** Asha (preparer) and the Fund ops users receive "NAV approved: Class A, Oct 31, 2026, ₹10,220.00", each once even if Asha is also tagged Fund ops

#### Scenario: Cut-off summary
- **WHEN** the daily check runs on 29 Oct 2026, the day after the 2 Nov dealing date's cut-off
- **THEN** Fund ops receive one summary for 2 Nov: 2 subscriptions (₹7,50,00,000), 1 unpaid (Q Capital ₹2,50,00,000 — will roll to 1 Dec 2026), 0 not ready, and 3 redemptions (₹6,50,00,000)

#### Scenario: Ready to confirm
- **WHEN** Ravi approves the 31 Oct NAV on 2 Nov 2026 at 10:00, after the 28 Oct cut-off
- **THEN** Fund ops and approvers receive "2 Nov 2026 is ready to confirm" with a link to the dealing date

#### Scenario: Gate applied
- **WHEN** Asha confirms 2 Nov 2026 with ₹1,39,00,000 carried forward (B LLP ₹39,00,000, C HUF ₹1,00,00,000)
- **THEN** Compliance and Fund ops receive "Gate applied on 2 Nov 2026: ₹5,11,00,000 paid, ₹1,39,00,000 carried to 1 Dec 2026"

#### Scenario: Large redemption
- **WHEN** D Partners, managed by Karan, redeems ₹2,50,00,000 on 10 Nov 2026 and class A's latest approved NAV is ₹102,20,00,000 (2.45 %), with the threshold at 2 %
- **THEN** Compliance and Karan receive "Large redemption: D Partners ₹2,50,00,000 (2.45 % of Class A NAV)"

#### Scenario: Redemption below the threshold
- **WHEN** C HUF redeems ₹1,00,00,000 when class A's NAV is ₹102,20,00,000 (0.98 %)
- **THEN** no large-redemption alert is sent

#### Scenario: Redemption payment overdue
- **WHEN** the daily check runs on 17 Nov 2026 and A Ltd's ₹3,00,00,000 redemption payment, due 16 Nov, is not marked paid
- **THEN** Fund ops receive "Settlement overdue on 2 Nov 2026" listing A Ltd ₹3,00,00,000, due Nov 16, 2026

#### Scenario: Pay-after money overdue
- **WHEN** Alpha pays after dealing (7 days), the 1 Dec 2026 dealing date is confirmed, and on 9 Dec Q Capital's ₹5,00,00,000 is still not received
- **THEN** Fund ops receive "Settlement overdue on 1 Dec 2026" listing Q Capital ₹5,00,00,000, pay by Dec 08, 2026

#### Scenario: Fee accrual behind
- **WHEN** Asha drafts the 30 Nov 2026 NAV while the management fee is accrued only to 31 Oct 2026
- **THEN** Fund accounting receive "Management fee accrued only to Oct 31, 2026 — run the fee formula to Nov 30, 2026 before approving"

#### Scenario: Documents awaiting approval
- **WHEN** Asha's Generate documents run for 2 Nov 2026 generates one contract note and two redemption advices
- **THEN** the approvers (Ravi and Asha) each receive one "Documents awaiting approval" alert for 2 Nov 2026, in-app and by email, saying "1 contract note and 2 redemption advices to approve" with a link to the dealing date

#### Scenario: Documents awaiting approval switched off
- **WHEN** Alpha has "Documents awaiting approval" switched off and a Generate documents run generates documents
- **THEN** no alert is sent

### Requirement: Per-fund switches with defaults
Each evergreen fund SHALL store its notification choices as `{ "<key>" => true/false, "reminder_days" => N, "large_redemption_pct" => X }`. A key that is missing SHALL use the default in the tables above (reminder days 2, large-redemption threshold 2 %), so a new notification needs only a default. The settings wizard SHALL have a "Notifications" step before Review, listing each switchable notification with a tooltip and its recipients. Reminder days SHALL be 1–30, and the threshold SHALL be greater than 0 and at most 100.

#### Scenario: Notifications step
- **WHEN** Asha opens the Notifications step of the settings wizard for Alpha
- **THEN** she sees every new investor notification and every internal alert with its switch at the default, a tooltip saying when it is sent, its recipients, reminder days 2 and threshold 2 %

#### Scenario: Switched off
- **WHEN** Asha switches "Payment reminder" off and saves, and the daily check runs on 26 Oct 2026 with Q Capital unpaid
- **THEN** Q Capital receives no payment reminder

#### Scenario: Default-off notification
- **WHEN** Alpha has never saved a "NAV update" choice and Ravi approves a NAV
- **THEN** no NAV update email is sent to investors

#### Scenario: Missing key uses the default
- **WHEN** Alpha's notification choices were saved before "Payment received" existed and a payment is verified
- **THEN** "Payment received" is sent, because its default is on

#### Scenario: Reminder days changed
- **WHEN** Asha sets reminder days to 3
- **THEN** the payment reminder and action-needed emails for the 2 Nov dealing date go out on 25 Oct 2026

#### Scenario: Invalid reminder days
- **WHEN** Asha enters reminder days 0 and saves
- **THEN** the settings are not saved and the field shows "must be between 1 and 30"

#### Scenario: Invalid threshold
- **WHEN** Asha enters a large-redemption threshold of 0 % or 120 % and saves
- **THEN** the settings are not saved and the field shows "must be greater than 0 and at most 100"

### Requirement: Each notification is sent once
The system SHALL record every notification it sends against the record it is about (order, payment, lot, NAV, dealing date) and SHALL NOT send it again for that record. Daily checks SHALL be recorded per day. Re-running a check or replaying an event SHALL send nothing twice. "Documents awaiting approval" SHALL be sent once per Generate documents run that generates at least one document; a run that generates nothing SHALL send nothing.

#### Scenario: Daily check run twice
- **WHEN** the daily check runs twice on 26 Oct 2026
- **THEN** Q Capital receives one payment reminder, not two

#### Scenario: Event replayed
- **WHEN** P Family Trust's verified payment is saved again (for example a reference correction)
- **THEN** no second "Payment received" email is sent

### Requirement: Copy customised notifications from another fund
On an evergreen fund's Notifications tab the system SHALL offer "Copy from fund…", listing the entity's other evergreen funds that have "Evergreen" custom notifications. Copying SHALL copy each enabled template (subject, body, attachment settings, show-details) to this fund, SHALL skip any email this fund already customises, SHALL overwrite nothing, and SHALL report "N copied, M skipped". Only users who can update the fund SHALL copy.

#### Scenario: Copy into a fund with none
- **WHEN** Alpha has no custom notifications, Gamma Income Fund (evergreen, same entity) has enabled templates for payment reminder, contract note and gate notice, and Asha copies from Gamma Income Fund
- **THEN** Alpha gets those three templates with the same subject, body, attachment settings and show-details, and Asha sees "3 copied, 0 skipped"

#### Scenario: Copy skips existing customisations
- **WHEN** Alpha already customises the contract note and Asha copies from Gamma Income Fund
- **THEN** Alpha's contract note template is unchanged, the other two are copied, and Asha sees "2 copied, 1 skipped"

#### Scenario: Nothing to copy from
- **WHEN** no other evergreen fund in the entity has Evergreen custom notifications
- **THEN** "Copy from fund…" shows "No other evergreen fund has custom notifications to copy"
