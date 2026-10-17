# Spec Delta

## Purpose

Adds phone push notifications as a delivery channel for every notification CapHive sends to
investors, gated by the same rules as email plus the investor's own category choices, with a tap
opening the exact item in the mobile app.

## ADDED Requirements

### Requirement: Devices register for push
The system SHALL let a signed-in phone register a push address. It SHALL also let the phone turn
push off or on for that device. A push address SHALL belong to at most one device. When a phone
registers an address already held by another device, the address SHALL move to the new device.

#### Scenario: Register on allow
- **WHEN** the LP allows notifications after signing in
- **THEN** the device stores the push address and shows push as on

#### Scenario: Same phone, new user
- **WHEN** a different user signs in on a phone whose push address is registered to the previous user
- **THEN** pushes for the previous user stop reaching that phone

### Requirement: Push follows the email gate
For every investor notification, the system SHALL send a push to each of the recipient's active
push-enabled devices if, and only if, all of the following hold:
- the email for that notification would be sent (the investor access has email enabled, or the
  recipient is an approved advisor for the record, and the notification has content);
- the recipient is not a member of the entity that sent it (internal notifications are never
  pushed);
- the recipient has the notification's category switched on.

#### Scenario: Capital call pushed
- **WHEN** a capital call notification is sent to an LP with email enabled and two active devices
- **THEN** both devices receive one push each

#### Scenario: Email disabled means no push
- **WHEN** the investor access has email disabled
- **THEN** no push is sent, and the notification still appears in the LP's in-app alert list

#### Scenario: Internal notification not pushed
- **WHEN** a notification goes to a member of the fund manager's own entity who also has the app
- **THEN** no push is sent

#### Scenario: Category switched off
- **WHEN** the LP has switched off "Distributions" and a distribution payment notification is sent
- **THEN** no push is sent and the email is unaffected

### Requirement: Notification categories
The system SHALL assign every investor notification to exactly one of four categories: Capital
calls & reminders, Distributions, Documents & signatures, or Everything else. A notification type
not explicitly assigned SHALL fall into Everything else. Category choices SHALL be stored per user,
SHALL apply to all their devices, and SHALL default to on.

#### Scenario: Unmapped type
- **WHEN** a new notification type with no category assignment is sent
- **THEN** it is treated as Everything else

### Requirement: Push content
A push SHALL carry the sending fund manager's name as its title and the notification's subject
line as its body, using the custom subject when the fund manager has set one. A push SHALL NOT
contain bank account numbers, document contents or more than 178 characters of body text. The
app badge SHALL show the recipient's unread notification count.

#### Scenario: Custom subject used
- **WHEN** the fund manager customised the capital call subject to "Arka Growth I — Call 3 notice"
- **THEN** the push body reads "Arka Growth I — Call 3 notice"

### Requirement: Tapping opens the item
A push SHALL carry a link to the record it concerns. The link SHALL open the matching app screen
for capital calls, funds and documents, and SHALL open the website page for every other record
through the website hand-off. Opening an item from a push SHALL mark that notification read.

#### Scenario: Capital call link
- **WHEN** the LP taps a capital call push
- **THEN** the Capital call screen for that remittance opens and the notification is marked read

#### Scenario: Access removed since push
- **WHEN** the LP taps a push for a record they no longer have access to
- **THEN** the app shows "You no longer have access to this item"

### Requirement: Dead devices are cleaned up
When the push service reports that a device is no longer registered, the system SHALL stop pushing
to that device and SHALL show "Last delivery: failed — device no longer registered" for it on the
Devices page. A push failure SHALL NOT affect email or WhatsApp delivery of the same notification.

#### Scenario: Reinstalled app
- **WHEN** the push service reports a device as not registered
- **THEN** further pushes skip that device and the email for the same notification is still delivered

### Requirement: Devices page on the website
The website SHALL show a signed-in user their phones (name, platform, region, last used, push on or
off, last delivery result) under Profile › Devices. Each phone SHALL have a **Sign out** action that
ends its session and stops pushes to it.

#### Scenario: Lost phone
- **WHEN** the user signs out "iPhone 15" on the Devices page
- **THEN** the device is listed as signed out and receives no further pushes
