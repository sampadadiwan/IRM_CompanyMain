# Spec Delta

## Purpose

Defines the behaviour of the CapHive LP mobile app for iOS and Android: a deliberately small set
of screens (four tabs and three detail screens) that let an investor check holdings, act on
capital calls, read and sign documents, and receive alerts.

## ADDED Requirements

### Requirement: Region is chosen before sign-in
The app SHALL ask for a region (India or US) on first launch, SHALL show the chosen region on the
sign-in screen with a Change action, and SHALL hold a session for one region at a time. Changing
region SHALL sign out of the current region.

#### Scenario: Wrong region
- **WHEN** a US-only user signs in with India selected
- **THEN** the app shows "Incorrect email or password" (never revealing whether the email exists) with the line "Is your account on the US site? Switch region"

### Requirement: Biometric unlock
After the first successful sign-in, the app SHALL offer Face ID or fingerprint unlock. Once enabled,
reopening the app after more than 5 minutes in the background SHALL require biometric unlock. After
3 failed biometric attempts, the app SHALL fall back to full sign-in. The app SHALL blur its content
in the system app switcher.

#### Scenario: Unlock on return
- **WHEN** the app returns from the background after 6 minutes with biometrics enabled
- **THEN** the app asks for Face ID before showing any data

### Requirement: Four tabs and three detail screens
The app SHALL have exactly the tabs Home, Documents, Alerts and Profile, and the detail screens Fund,
Capital call and Document. Any other item SHALL open on the website in the in-app browser through
the website hand-off.

#### Scenario: KYC from Alerts
- **WHEN** the LP taps a KYC alert
- **THEN** the website's KYC page opens in the in-app browser, signed in

### Requirement: Home
Home SHALL show a To do card and one card per fund. Fund cards SHALL show committed, called (with
the called percentage as a bar), due and distributed amounts, in compact form (₹5.00 Cr, $1.2M).
Evergreen funds SHALL show value, units, NAV per unit with its date, and gain. With no to-do items,
the card SHALL read "You're all caught up". Users with more than one investor persona SHALL see an
investor switcher.

#### Scenario: Caught up
- **WHEN** the LP has no unpaid calls and nothing to sign
- **THEN** the To do card reads "You're all caught up"

### Requirement: Fund screen
The Fund screen SHALL show the exact totals and the segments Calls, Distributions and Documents
(Holding, Transactions and Documents for evergreen funds). Evergreen Subscribe and Redeem SHALL open
the website wizard in the in-app browser.

#### Scenario: Calls listed
- **WHEN** the LP opens Arka Growth Fund I
- **THEN** Calls lists Capital Call 3 ₹75,00,000 Pending, Capital Call 2 ₹50,00,000 Paid and Capital Call 1 ₹75,00,000 Paid

### Requirement: Capital call screen
The Capital call screen SHALL show the call name, fund, status, call amount, amount received and
due date, with View call notice as its primary action. View call notice SHALL open the call's
notice document for this investor. When no notice exists, the screen SHALL read "The call notice
isn't available yet".

#### Scenario: Open the notice
- **WHEN** the LP taps View call notice on Capital Call 3
- **THEN** the Capital Call 3 notice for Sharma Family Office opens in the document viewer

#### Scenario: No notice yet
- **WHEN** the remittance has no notice document
- **THEN** the screen reads "The call notice isn't available yet"

### Requirement: Document screen and signing
The Document screen SHALL open the document in the in-app viewer and offer a Share action. When the user is a
pending signatory, it SHALL show Sign. For Digio documents, Sign SHALL open Digio's signing page in
the app and refresh the status on return. For DocuSign documents, it SHALL read "Sign in DocuSign
email" with the explanation "Open the email from DocuSign on this phone to sign". Sign SHALL be
disabled while offline.

#### Scenario: Digio signing
- **WHEN** the LP signs a Digio side letter in the app and returns
- **THEN** the document shows "Signed ✓"

### Requirement: Alerts and badge
The Alerts tab SHALL list the user's notifications, newest first, with unread items marked, a
swipe-to-mark-read action and Mark all read. Read state SHALL be shared with the website bell.

#### Scenario: Read on website
- **WHEN** the LP marks an alert read on the website
- **THEN** it shows as read in the app after the next refresh

### Requirement: Notification permission and settings
The app SHALL ask for notification permission only after the first successful sign-in, with the
explanation "Get notified when a capital call or document needs you". Profile › Notifications SHALL
show the four category switches. When the phone's permission is off, it SHALL say so and offer Open
phone settings.

#### Scenario: Permission denied at system level
- **WHEN** the phone's notification permission is off
- **THEN** Profile › Notifications shows "Off in phone settings" with an Open phone settings button

### Requirement: Display formats
The app SHALL format dates with the signed-in user's locale date format from the server
(`dd/mm/yyyy` for India English, `mm/dd/yyyy` for US English). It SHALL format amounts in the fund's
currency, with lakh/crore grouping for INR. Detail screens SHALL show exact amounts.

#### Scenario: Indian date
- **WHEN** an India-region user with the `en` locale views a due date of 30 October 2026
- **THEN** it reads 30/10/2026

### Requirement: Offline and errors
The app SHALL show the last loaded data when offline, with a "Last updated HH:MM — offline" bar.
Every failed load SHALL show a plain-language message with Try again. The app SHALL NOT show raw
error codes.

#### Scenario: Offline Home
- **WHEN** the phone has no connection
- **THEN** Home shows cached cards and the offline bar

### Requirement: Forced update
When the server answers "update required", the app SHALL show "Please update CapHive to continue"
with a link to the store, and SHALL block further use.

#### Scenario: Update required
- **WHEN** the server reports the app version is below the minimum
- **THEN** the update screen is shown

### Requirement: Accessibility and theme
The app SHALL use one designed theme — graphite surfaces with CapHive orange as the accent — that
does not change with the phone's light/dark setting, and SHALL follow the phone's text size. It
SHALL give every control a screen-reader label, SHALL use touch targets of at least 44 points, and
SHALL never convey status by colour alone.

#### Scenario: Large text
- **WHEN** the phone's text size is set to the largest accessibility size
- **THEN** Home remains readable without overlapping or truncated amounts
