# Spec Delta

## Purpose

Delivers automated email notifications across the NDA lifecycle — accept, decline, revoke, version change, expiry approaching, expired, acceptance confirmation to LP users, and GP-triggered bulk reminders — so that both GP teams and LP users stay informed without manual dashboard checks.

## ADDED Requirements

### Requirement: GP team receives accept notification
The system SHALL send an email to every address in the NdaConfig's notification_emails field when an LP accepts the NDA.

#### Scenario: LP accepts NDA with notification recipients configured
- **WHEN** an LP user accepts an NDA on a folder whose NdaConfig has notification_emails set
- **THEN** each email address in notification_emails receives an email containing the investor name, folder name, NDA version, signing user name, and date/time

#### Scenario: LP accepts NDA with no notification recipients
- **WHEN** an LP user accepts an NDA on a folder whose NdaConfig has notification_emails blank
- **THEN** no GP accept notification email is sent

### Requirement: GP team receives decline notification
The system SHALL send an email to every address in the NdaConfig's notification_emails field when an LP declines the NDA.

#### Scenario: LP declines NDA with notification recipients configured
- **WHEN** an LP user declines an NDA on a folder whose NdaConfig has notification_emails set
- **THEN** each email address in notification_emails receives an email containing the investor name, folder name, NDA version, declining user name, and date/time

### Requirement: LP users receive acceptance confirmation
The system SHALL send a confirmation email to all other InvestorAccess users of the accepting investor's entity when the NDA is accepted, excluding the signing user.

#### Scenario: NDA accepted — investor has multiple users
- **WHEN** User A accepts the NDA on behalf of Investor X, and Investor X has two other users (B and C) with approved InvestorAccess on the entity
- **THEN** User B and User C each receive a confirmation email containing the folder name, who signed, date/time, and a link to the folder
- **THEN** User A does not receive a confirmation email

#### Scenario: NDA accepted — investor has only one user
- **WHEN** User A accepts the NDA on behalf of Investor X, and User A is the only user with InvestorAccess for Investor X
- **THEN** no confirmation email is sent

#### Scenario: NDA accepted — exempt investor's users not notified
- **WHEN** a user accepts on behalf of an exempt investor
- **THEN** no confirmation email is sent (exempt investors bypass the NDA gate)

### Requirement: LP users notified on revocation
The system SHALL send an email to all InvestorAccess users of the revoked investor when a GP revokes the NDA acceptance.

#### Scenario: GP revokes accepted investor
- **WHEN** the GP revokes the NDA acceptance for Investor X
- **THEN** all users of Investor X with approved InvestorAccess on the entity receive a revocation email containing the folder name and contact_email for questions

### Requirement: LP users notified on NDA version change
The system SHALL send an email to all InvestorAccess users of previously-accepted investors when the NdaConfig version is incremented by a new PDF upload.

#### Scenario: GP uploads new NDA PDF — investors had accepted old version
- **WHEN** the GP uploads a new NDA PDF on a folder, causing the version to increment from N to N+1, and three investors had accepted version N
- **THEN** all InvestorAccess users of those three investors receive a version change email containing the folder name, old version, new version, and a link to re-accept
- **THEN** investors who were Pending, Declined, Revoked, or Exempt do not receive the notification

#### Scenario: GP uploads new NDA PDF — no investors had accepted
- **WHEN** the GP uploads a new NDA PDF and no investors have accepted any version
- **THEN** no version change notifications are sent

### Requirement: GP team receives expiry approaching alert
The system SHALL send an email to the NdaConfig's notification_emails 7 days before an NDA acceptance expires, for NDAs with fixed_period or specific_date validity.

#### Scenario: Fixed-period NDA acceptance approaching expiry
- **WHEN** a daily job runs and an investor's acceptance was created (validity_days − 7) days ago for a fixed_period NDA
- **THEN** each address in notification_emails receives an expiry-approaching email containing the investor name, folder name, and expiry date

#### Scenario: Specific-date NDA approaching expiry
- **WHEN** a daily job runs and an NdaConfig with specific_date validity has validity_date exactly 7 days from today
- **THEN** each address in notification_emails receives an expiry-approaching email for every accepted investor on that NDA

#### Scenario: Until-revoked NDA never triggers expiry
- **WHEN** a daily job runs and an NdaConfig has until_revoked validity
- **THEN** no expiry alert is sent regardless of acceptance age

### Requirement: LP signatories receive expiry approaching alert
The system SHALL send an expiry-approaching email to the NDA signatories of the investor whose acceptance is approaching expiry.

#### Scenario: Signatory receives 7-day expiry warning
- **WHEN** an acceptance is 7 days from expiry and the investor has designated NDA signatories
- **THEN** each signatory receives an expiry-approaching email with the folder name, expiry date, and a link to re-accept

#### Scenario: No signatories designated — no LP expiry alert
- **WHEN** an acceptance is 7 days from expiry but the investor has no NDA signatories
- **THEN** no LP-side expiry alert is sent (GP still receives their alert)

### Requirement: GP team receives expired alert
The system SHALL send an email to the NdaConfig's notification_emails on the day an NDA acceptance expires.

#### Scenario: Acceptance expires today
- **WHEN** a daily job runs and an investor's acceptance has reached its expiry date
- **THEN** each address in notification_emails receives an expired email containing the investor name, folder name, and expiry date

### Requirement: LP signatories receive expired alert
The system SHALL send an expired email to the NDA signatories of the investor whose acceptance has expired.

#### Scenario: Signatory notified on expiry day
- **WHEN** an acceptance expires and the investor has designated NDA signatories
- **THEN** each signatory receives an expired email with the folder name and a link to re-accept

### Requirement: Expiry alerts are idempotent
The system SHALL send each expiry alert (approaching or expired) at most once per investor per expiry event, even if the daily job runs multiple times.

#### Scenario: Daily job runs twice — no duplicate alert
- **WHEN** the daily expiry job runs, sends an approaching-expiry alert for Investor X, and the job runs again later the same day
- **THEN** no duplicate alert is sent for Investor X

### Requirement: GP sends bulk reminders to pending investors
The system SHALL allow the GP to send NDA reminder emails to NDA signatories of investors with Pending status from the NDA Status Dashboard.

#### Scenario: GP sends reminders — pending investors exist
- **WHEN** the GP clicks "Send Reminders" on the NDA Status Dashboard and confirms the dialog
- **THEN** each NDA signatory of each Pending investor receives a reminder email directing them to the folder to accept the NDA
- **THEN** a success flash message shows "Reminders sent to X users"

#### Scenario: GP sends reminders — no pending investors
- **WHEN** the GP views the NDA Status Dashboard and no investors have Pending status
- **THEN** the "Send Reminders" button is disabled or a message "No pending investors to remind" is shown

#### Scenario: Pending investor has no signatories
- **WHEN** the GP sends reminders and one pending investor has no designated NDA signatories
- **THEN** no reminder is sent for that investor; other pending investors with signatories still receive reminders

### Requirement: Notifications are sent in the background
The system SHALL send all NDA notification emails via background jobs, never blocking the user's request.

#### Scenario: LP acceptance is not delayed by notifications
- **WHEN** an LP accepts the NDA
- **THEN** the acceptance response returns immediately; notification emails are enqueued for background delivery

### Requirement: Exempt investors do not receive notifications
The system SHALL NOT send reminders, expiry alerts, or version change notifications to exempt investors.

#### Scenario: Exempt investor excluded from reminders
- **WHEN** the GP sends reminders and an investor is exempt
- **THEN** that investor's signatories do not receive a reminder email

#### Scenario: Exempt investor excluded from expiry alerts
- **WHEN** the daily job checks expiry and an investor is exempt
- **THEN** no expiry alert is sent for that investor
