# identity/two-factor-authentication Specification

## Purpose
Defines which users must sign in with a second factor, how every sign-in door applies that rule,
how any user turns two-factor off, how a lost method is recovered and announced, and how the
requirement is rolled out separately in each regional deployment.

## Requirements

### Requirement: CapHive support and super users require two-factor after the region's enforcement date

The system SHALL treat two-factor authentication as required for any user holding a role in the
required-roles list once the deployment's configured enforcement date has been reached. The
required-roles list SHALL contain the support and super roles, and SHALL be defined in exactly one
place so that adding or removing a role is a single change. Each regional deployment SHALL have
its own enforcement date; when no date is configured the requirement SHALL NOT apply in that
deployment. Whether two-factor is required SHALL be derived from the user's current roles at the
moment of sign-in, not from a stored per-user flag. Users holding no required role — including
company admins of fund and investor firms — SHALL keep two-factor optional, with behaviour
unchanged.

#### Scenario: Support user without a method signs in after the date
- **WHEN** a support user with no verified two-factor method enters a correct password on or after the enforcement date
- **THEN** the user is not signed in and is shown the two-factor set-up screen with the message "Two-factor authentication is required for your role (Support). Choose a method to finish signing in."

#### Scenario: Support user with a method signs in after the date
- **WHEN** a support user with a verified authenticator method enters a correct password after the enforcement date
- **THEN** the code screen is shown and the user is signed in only after a correct code

#### Scenario: Support user signs in before the date
- **WHEN** a support user without two-factor signs in before the enforcement date
- **THEN** the user is signed in with the password alone, as today

#### Scenario: No enforcement date configured
- **WHEN** no enforcement date is configured and a support user without two-factor signs in
- **THEN** the user is signed in with the password alone, and no banner is shown

#### Scenario: Support role granted after the date
- **WHEN** a user without two-factor is given the support role after the enforcement date and later signs in
- **THEN** the set-up screen is shown before the user is signed in

#### Scenario: Company admin is not required
- **WHEN** a company admin without two-factor signs in after the enforcement date
- **THEN** the user is signed in with the password alone, as today

#### Scenario: Super user is required
- **WHEN** a user holding the super role but not the support role, without two-factor, signs in after the enforcement date
- **THEN** the set-up screen is shown with "Two-factor authentication is required for your role (Super). Choose a method to finish signing in."

#### Scenario: Other users are unaffected
- **WHEN** an investor or employee signs in after the enforcement date
- **THEN** sign-in behaves exactly as today, asking for a code only if the user switched two-factor on

### Requirement: Required set-up never locks a user out

Set-up required by role SHALL use the existing method-selection and confirmation screens. The
authenticator-app method SHALL always be offered, whether or not a phone number is held. Nothing
SHALL be stored until a code for the chosen method has been confirmed; on confirmation the system
SHALL store the method and switch two-factor on for the user. Three wrong codes SHALL end the
attempt and return the user to the sign-in page.

#### Scenario: Authenticator offered without a phone number
- **WHEN** a support user with no phone number reaches required set-up
- **THEN** the authenticator-app option is offered and selected

#### Scenario: Confirmation switches two-factor on
- **WHEN** a support user whose two-factor switch was off confirms a correct code during required set-up
- **THEN** two-factor is on with the chosen method stored, the user is signed in, and "Two-factor authentication is now enabled." is shown

#### Scenario: Abandoned set-up stores nothing
- **WHEN** a support user leaves required set-up before confirming a code and signs in again later
- **THEN** no method is stored and the set-up screen is shown again

#### Scenario: Three wrong set-up codes
- **WHEN** a support user enters three wrong codes during required set-up
- **THEN** the user is returned to the sign-in page with "Too many failed attempts. Please sign in again." and nothing is stored

### Requirement: Every sign-in door applies the same two-factor rule

The magic-link sign-in, the password-reset completion, the password token endpoint and the LP
mobile app sign-in SHALL apply the same rule as password sign-in: two-factor applies when it is
switched on for the user or required by the user's role. Credentials minted from a signed-in
website session (named API tokens, MCP authorisations, mail add-in tokens) SHALL continue to work
for users with a verified method.

#### Scenario: Magic link for a support user without a method
- **WHEN** a support user without a verified method opens a valid sign-in link after the enforcement date
- **THEN** the set-up screen is shown instead of signing the user in

#### Scenario: Password reset does not sign a required user in
- **WHEN** a support user without two-factor completes a password reset after the enforcement date
- **THEN** the user is sent to the sign-in page rather than signed in

#### Scenario: Password token endpoint refuses a required user
- **WHEN** a support user without two-factor posts a correct email and password to the password token endpoint after the enforcement date
- **THEN** the response is 403 with error `two_factor_required` and no token is issued

#### Scenario: Wrong password at the token endpoint is unchanged
- **WHEN** a support user posts a wrong password to the password token endpoint
- **THEN** the response is the endpoint's normal invalid-credentials answer and the failed attempt counts toward the account lock

#### Scenario: Mobile app sign-in for a required user without a method
- **WHEN** a support user who also holds the investor role and has no verified method signs in to the LP mobile app after the enforcement date
- **THEN** the response is the existing `finish_2fa_setup` refusal and no device session is issued

#### Scenario: Website-minted token keeps working
- **WHEN** a support user with a verified method uses a named API token created from Profile › API tokens after the enforcement date
- **THEN** the request is served as before

### Requirement: Support and super users are told before and after the date

While a user holding a required role without a verified method is signed in and an enforcement
date is configured, every page SHALL show a banner naming the role and the date. Before the date
the banner SHALL say when the requirement starts; on or after it the banner SHALL say it is now
required and that Login as is unavailable. The banner SHALL offer "Set up now", which SHALL switch
two-factor on for that user, sign them out and show "Sign in again to set up two-factor
authentication." The banner and "Set up now" SHALL NOT be offered to users without a required role,
nor while a support user is acting as a client.

#### Scenario: Notice banner before the date
- **WHEN** a support user without two-factor views any page before an enforcement date of 1 Dec 2026
- **THEN** a banner reads "Two-factor authentication becomes required for your role (Support) on 01/12/2026." with a "Set up now" button

#### Scenario: Required banner after the date
- **WHEN** a support user without a verified method, still signed in from before the date, views a page after it
- **THEN** a banner reads "Two-factor authentication is now required for your role. Set it up to keep using CapHive. Login as is unavailable until you do."

#### Scenario: Set up now
- **WHEN** the support user presses "Set up now"
- **THEN** two-factor is switched on for the user, the user is signed out, and "Sign in again to set up two-factor authentication." is shown

#### Scenario: No banner for users without a required role
- **WHEN** a company admin without two-factor views a page after the enforcement date
- **THEN** no two-factor banner is shown and a direct "Set up now" request is refused

#### Scenario: No banner once set up or while acting as a client
- **WHEN** a support user has a verified method, or a support user is acting as a client user
- **THEN** no two-factor banner is shown

### Requirement: Login as requires the acting user's own verified two-factor

On or after the enforcement date, the system SHALL refuse a request to act as a client user unless
the requesting support or super user has a verified two-factor method (both are required roles, so
this closes sessions that began before the date). The client user's own
two-factor SHALL continue not to be asked for. Before the date the existing rules SHALL apply
unchanged.

#### Scenario: Support user without a method is refused
- **WHEN** a support user without a verified method, with an enabled mapping that allows Login as, requests Login as after the enforcement date
- **THEN** the request is refused with "Set up two-factor authentication before using Login as." and no client session starts

#### Scenario: Support user with a method acts as the client
- **WHEN** a support user with a verified method requests Login as for a mapped client user who has two-factor on
- **THEN** the support user acts as the client user without the client's code being asked for

#### Scenario: Login as before the date is unchanged
- **WHEN** a support user without two-factor requests Login as before the enforcement date
- **THEN** the request is allowed as today

### Requirement: Turning two-factor off requires the password and a current code

This requirement SHALL apply to every user who has two-factor on, whether it is required by role or
was switched on voluntarily (for example a company admin), so that a stolen session cannot silently
remove it. A user SHALL be able to switch their own two-factor off only through a confirmation on
their own user page that checks their password and, when a method is stored, a current code for
that method. A wrong password SHALL count toward the account lock. Wrong codes SHALL count toward
the existing hourly two-factor limit, and three wrong codes within 10 minutes SHALL refuse further
attempts for the rest of that window. Switching two-factor off by any other route — the edit form,
a JSON request, the admin console, or another user acting on the account — SHALL be refused. A copy
received from the user's origin region through the cross-region sync SHALL still be applied.

#### Scenario: Turn off with password and code
- **WHEN** an investor with WhatsApp two-factor enters the correct password and the WhatsApp code just sent, and confirms
- **THEN** two-factor is off, the stored method is forgotten, the investor stays signed in and sees "Two-factor authentication is now off. You will sign in with just your password."

#### Scenario: Company admin's voluntary two-factor needs the same proof
- **WHEN** a company admin who switched two-factor on voluntarily turns it off after the enforcement date
- **THEN** the password and a current code are required exactly as for any other user

#### Scenario: Stolen session cannot remove two-factor
- **WHEN** someone holding a company admin's signed-in browser, without the password, submits the turn-off confirmation or unticks two-factor on the edit form
- **THEN** two-factor stays on

#### Scenario: Wrong password
- **WHEN** the user enters a wrong password in the turn-off confirmation
- **THEN** two-factor stays on, "The password you entered is incorrect." is shown, and the failed attempt counts toward the account lock

#### Scenario: Wrong code
- **WHEN** the user enters the correct password and a wrong code
- **THEN** two-factor stays on and "The code you entered is incorrect. 2 attempt(s) remaining." is shown

#### Scenario: Third wrong code within 10 minutes
- **WHEN** the user enters a third wrong code within 10 minutes
- **THEN** two-factor stays on and "Too many incorrect codes. Try again in 10 minutes." is shown, even for a correct code in that window

#### Scenario: Two-factor on but no method stored
- **WHEN** a user whose two-factor is on but who never confirmed a method enters the correct password and confirms
- **THEN** two-factor is switched off without a code being asked for

#### Scenario: Edit form or JSON update tries to switch it off
- **WHEN** an update to the user record submits two-factor as off, from the edit form, a JSON request or the admin console
- **THEN** the update is refused with "Two-factor authentication can only be turned off from your user page, with your password and a current code." and two-factor stays on

#### Scenario: Another user cannot switch it off
- **WHEN** a company admin requests the turn-off for another user of their firm
- **THEN** the request is refused as access denied

#### Scenario: Switching on from the edit form is unchanged
- **WHEN** a user with two-factor off ticks "Enable Two-Factor Authentication" and saves
- **THEN** two-factor is on and the user chooses a method at the next sign-in, as today

#### Scenario: Cross-region sync applies the origin's change
- **WHEN** the origin region syncs a user whose two-factor was switched off there
- **THEN** the destination region applies the change

### Requirement: Required users cannot switch two-factor off

A user for whom two-factor is required by role SHALL NOT be offered the turn-off action, and a
direct turn-off request from such a user SHALL be refused with "Two-factor authentication is
required for your role and cannot be turned off." Their user page SHALL show "Required for your
role".

#### Scenario: Required user sees no turn-off
- **WHEN** a support user with a verified method opens their own user page after the enforcement date
- **THEN** a "Required for your role" badge is shown and no "Turn off 2FA" button

#### Scenario: Direct turn-off request from a required user
- **WHEN** a support user posts the turn-off request directly with the correct password and code after the enforcement date
- **THEN** two-factor stays on and "Two-factor authentication is required for your role and cannot be turned off." is shown

### Requirement: Lost methods are recovered by an audited administrator reset

A user who cannot produce a code SHALL be recovered by the existing method reset, performed by a
company admin of the user's firm or by support. The reset SHALL keep two-factor on, record who
performed it in the audit log, email the user, and email the firm's other company admins when the
reset was performed by someone other than the user. At the next sign-in the user SHALL be taken to
set-up.

#### Scenario: Support resets a support user's lost method
- **WHEN** a support user resets another support user's method after the enforcement date
- **THEN** two-factor stays on, the method is cleared, the reset is recorded with the actor, the user and their firm's other company admins are emailed, and the user's next sign-in shows the set-up screen

### Requirement: Two-factor changes are announced by email

The system SHALL email the user when a method is confirmed (two-factor switched on) and when
two-factor is switched off. When two-factor is switched off, the system SHALL also email the other
company admins of the user's firm. Each email SHALL be sent once per change and SHALL show dates in
the email date format.

#### Scenario: Switched on email
- **WHEN** a user confirms a method
- **THEN** the user receives "Two-factor authentication was turned on for your account" naming the method

#### Scenario: Switched off emails
- **WHEN** an investor switches two-factor off and their firm has two other company admins
- **THEN** the investor receives "Two-factor authentication was turned off for your account" and each of the two company admins receives a notice naming the investor

### Requirement: Roll-out is measured and run separately per region

Operations SHALL be able to, in each region separately: report how many users holding a required
role have and lack a verified method, without any names or email addresses; and, once the
enforcement date is reached, end the "remember me" sign-ins and revoke the website-minted tokens of
users holding a required role without a verified method, so that their next visit passes through
sign-in. The ending task SHALL change nothing unless explicitly told to execute, and SHALL refuse
to run before the enforcement date.

#### Scenario: Report shows counts only
- **WHEN** operations runs the report
- **THEN** it prints, per required role, counts of active users with and without a verified method and of those signed in within 90 days, notes roles that are not required, and prints no names or emails

#### Scenario: Ending access dry run changes nothing
- **WHEN** operations runs the ending task without the execute switch after the date
- **THEN** it prints how many users would be affected and every "remember me" cookie and token keeps working

#### Scenario: Ending access for unverified support users
- **WHEN** operations runs the ending task with the execute switch after the date
- **THEN** the "remember me" cookies and named API / MCP tokens of support and super users without a verified method stop working, and other users are untouched

#### Scenario: Ending access refused before the date
- **WHEN** operations runs the ending task before the enforcement date
- **THEN** it prints that the date has not been reached and changes nothing
