# Spec Delta

## MODIFIED Requirements

### Requirement: Journey panel on the distribution page
A distribution with a journey SHALL show the step bar (every task by name with its mark) and a "What's
needed now" panel naming the current task, a specific message and, where one exists, a button. The button
SHALL activate the control on the page that does the work (opening its menu and running its own
confirmation); when that control is not on the page it SHALL act as a link. Readiness warnings (Skip Doc Gen
commitments, investors with nobody subscribed to Distribution emails, KYCs without bank details, KYCs whose
bank details changed and are not yet confirmed by a second approver) SHALL show until Email investors passes
or is not applicable. The panel SHALL be the only place journey state appears: confirmation dialogs SHALL NOT
repeat it.

#### Scenario: Panel while notices are partly approved
- **WHEN** 1 of 3 generated notices is approved and the user opens the distribution
- **THEN** the panel says "Approve notices: 2 of 3 notices await approval" and its "View notices to approve" button clicks the Actions menu's "View Generated Notices To Approve"

#### Scenario: Panel button runs the real control
- **WHEN** the current task is Mark payments completed and the user clicks the panel button
- **THEN** the Actions menu's "Mark Payments Completed" confirmation appears, and confirming completes the payments

#### Scenario: Notices not used
- **WHEN** the fund has no Distribution Template
- **THEN** Generate notices and Approve notices show as not applicable with "No distribution notice template"

#### Scenario: Warnings until emailed
- **WHEN** one commitment is set to Skip Doc Gen and investors have not been emailed
- **THEN** the panel warns "1 commitment has Skip Doc Gen set and will not be emailed", and the warning disappears once Email investors passes

#### Scenario: Unconfirmed bank change warning
- **WHEN** one paid investor's KYC has a bank change awaiting a second approver and investors have not been emailed
- **THEN** the panel warns "1 KYC has bank details changed and not yet confirmed by a second approver", and the warning disappears once the KYC is verified by a second approver
