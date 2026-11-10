Feature: Turning two-factor off needs the password and a current code — for every user
  Unticking "Enable Two-Factor Authentication" used to need nothing, so a stolen session could remove
  anyone's second factor. Now two-factor goes off only from the user's own page, in a popup that asks
  for the password and a current code (TwoFactorDisable), for every user who has it on — a company
  admin's or an investor's voluntary two-factor as much as a support user's. Support and super users
  cannot turn it off at all (required from the deploy). The user and the firm's other company admins
  are emailed; an administrator's reset of a colleague's method is told to them too.
  Design: openspec/changes/archive/2026-11-10-require-2fa-privileged-roles (business-rules.md §3, H9–H11, E30–E41, X11–X14; E42 retired with the date).

  Background:
    Given it is "2026-12-08 10:00" in India

  # ── Happy path ────────────────────────────────────────────────────────────────

  # H9 — Happy path: an investor turns off WhatsApp two-factor in the real popup (Send code, code, tick, submit)
  @stub-whatsapp @two_factor_cache
  Scenario: H9 Investor turns off with a WhatsApp code
    Given the people "Priya, Rahul, Sunita" exist
    And "Priya" is signed in on the website
    And I enter the WhatsApp OTP to verify
    And 1 minutes pass
    When I open my user page
    And I turn off two-factor in the popup with password "password"
    Then I should see "Two-factor authentication is now off. You will sign in with just your password."
    And "Priya" has two-factor off with no method
    And the audit log records the turn-off of "Priya"
    And "Priya" is emailed "Two-factor authentication was turned off for your account" dated "Dec 08, 2026"
    And "Rahul" is emailed "Two-factor was turned off for Priya Tester"
    And the email "Two-factor was turned off for Priya Tester" to "Rahul" says "you are a company admin of the same firm"
    And the email "Two-factor authentication was turned off for your account" to "Priya" says "If you did not make this change"
    And "Sunita" is emailed "Two-factor was turned off for Priya Tester"

  # H10 — Happy path: a company admin turns off her voluntary two-factor; the firm's other company admins are told
  @rack_test @two_factor_cache
  Scenario: H10 Company admin turns off voluntary two-factor
    Given the people "Neha, Meera, Omkar" exist
    And "Neha" is signed in on the website with their code
    And 1 minutes pass
    When I submit the turn-off popup with password "password" and the current code
    Then I should see "Two-factor authentication is now off."
    And "Neha" has two-factor off with no method
    And "Neha" is emailed "Two-factor authentication was turned off for your account"
    And "Meera" is emailed "Two-factor was turned off for Neha Tester"
    And "Omkar" is emailed "Two-factor was turned off for Neha Tester"

  # H11 — Happy path: support resets a support user's lost method; CapHive's company admin is told; the next sign-in is set-up
  @rack_test
  Scenario: H11 Support resets a support user's lost method
    Given it is "2026-12-05 10:00" in India
    And the people "Ravi, Leela" exist
    And "Ravi" has set up the authenticator app
    And "Anita" is signed in on the website with their code
    When I open the user page of "Ravi"
    And I confirm the admin reset with message "As discussed on the phone"
    Then I should see "Two-factor method reset for Ravi Tester"
    And "Ravi" has two-factor on with no method
    And "Ravi" is emailed "Your two-factor authentication method was reset"
    And "Leela" is emailed "Two-factor method reset for Ravi Tester"
    When "Ravi" signs in with their password
    Then I see the required set-up screen for the role "Support"

  # ── Edge cases ────────────────────────────────────────────────────────────────

  # E30 — Edge case: two-factor on but no method stored — the popup asks for the password only
  @rack_test
  Scenario: E30 No method means password only
    Given "Lena" signed in before switching two-factor on
    And "Lena" has two-factor on with no method
    When I open my user page
    Then the turn-off popup has no code field
    And the turn-off popup explains why the password and code are asked
    When I submit the turn-off popup with password "password" and no code
    Then I should see "Two-factor authentication is now off."
    And "Lena" has two-factor off with no method

  # E31 — Edge case: Edit profile no longer offers to switch two-factor off — it points to the user page
  @rack_test
  Scenario: E31 Edit form when two-factor is on
    Given "Dev" is signed in on the website with their code
    When I open my Edit profile
    Then I should see "On — turn it off from your user page, with your password and a current code."
    And I should not see "Enable Two-Factor Authentication"

  # E32 — Edge case: switching two-factor ON from Edit profile is unchanged
  @rack_test
  Scenario: E32 Turning on from the edit form is unchanged
    Given "Arjun" is signed in on the website
    When I open my Edit profile
    And I check "user_two_factor_enabled"
    And I click on "Save"
    Then I should see "User was successfully updated."
    And "Arjun" has two-factor on with no method
    When "Arjun" signs in with their password
    Then I should be on the 2FA mode selection page

  # E33 — Edge case: the cross-region sync applies the origin's own turn-off
  @rack_test
  Scenario: E33 Sync applies the origin's turn-off
    Given the server region is "US" and an HMAC secret is configured
    And "Priya" lives in IN and US
    When the origin region syncs "Priya" with two-factor switched off
    Then the response status should be 200
    And the JSON response should include "applied" = true
    And "Priya" has two-factor off with no method

  # E34 — Edge case: one wrong code, then the right one
  @rack_test @two_factor_cache
  Scenario: E34 Wrong code then the right one
    Given "Dev" is signed in on the website with their code
    And 1 minutes pass
    When I submit the turn-off popup with password "password" and the code "000000"
    Then I should see "The code you entered is incorrect. 2 attempt(s) remaining."
    When I submit the turn-off popup with password "password" and the current code
    Then I should see "Two-factor authentication is now off."

  # E35 — Edge case: a support user sees "Required for your role" (tooltip names the role) and no Turn off
  @rack_test
  Scenario: E35 Required user sees no turn-off
    Given "Anita" is signed in on the website with their code
    When I open my user page
    Then I see the "Required for your role" badge with a tooltip naming "Support"
    And I see no "Turn off 2FA" button
    When I open my Edit profile
    Then I should see "Required for your role (Support)."

  # E36 — Edge case: an SMS user presses Send code and turns off with the texted code
  @rack_test @stub-twilio @two_factor_cache
  Scenario: E36 SMS user turns off
    Given "Tom" is signed in on the website
    And I enter the texted code
    And 2 minutes pass
    When I press Send code on my user page
    Then I should see "A new code is on its way."
    When I open my user page
    And I submit the turn-off popup with password "password" and the current code
    Then I should see "Two-factor authentication is now off."
    And "Tom" has two-factor off with no method

  # E37 — Edge case: a second Send code within the cooldown is refused; only one code goes out
  @rack_test @stub-whatsapp @two_factor_cache
  Scenario: E37 Send code cooldown
    Given "Priya" is signed in on the website
    And I enter the WhatsApp OTP to verify
    When I press Send code on my user page
    Then I should see "A new code is on its way."
    When I press Send code on my user page
    Then I should see "Please wait a moment before requesting another code."
    And WhatsApp codes were sent 2 times

  # E38 — Edge case: a company admin on an employee's page sees Reset, and Turn off disabled with the reason
  @rack_test
  Scenario: E38 Admin sees Reset, and Turn off disabled with the reason
    Given the people "Dev" exist
    And "Neha" is signed in on the website with their code
    When I open the user page of "Dev"
    Then I see the "Reset 2FA Method" button
    And the Turn off 2FA control is disabled with the hint "Only the user can turn off their own 2FA. Use Reset 2FA Method if they lost their phone."

  # E39 — Edge case: a self-service method change emails only the user
  @rack_test
  Scenario: E39 Self reset sends no admin notice
    Given the people "Neha, Meera, Omkar" exist
    And "Dev" is signed in on the website with their code
    When I submit a self reset with password "password"
    Then "Dev" is emailed "Your two-factor authentication method was reset"
    And "Neha" is not emailed "Two-factor method reset"
    And "Meera" is not emailed "Two-factor method reset"

  # E40 — Edge case: with no other active company admin in the firm, only the user is emailed
  @rack_test @stub-whatsapp @two_factor_cache
  Scenario: E40 No other company admins
    Given the people "Rahul, Sunita" exist
    And "Rahul" is no longer active
    And "Sunita" is no longer active
    And "Priya" is signed in on the website
    And I enter the WhatsApp OTP to verify
    And 1 minutes pass
    When I submit the turn-off popup with password "password" and the current code
    Then I should see "Two-factor authentication is now off."
    And "Priya" is emailed "Two-factor authentication was turned off for your account"
    And "Rahul" is not emailed "Two-factor was turned off"
    And "Sunita" is not emailed "Two-factor was turned off"

  # E41 — Edge case: processed under the ja locale, the email date still reads "Dec 08, 2026" (not kanji)
  @stub-whatsapp
  Scenario: E41 Email date under the ja locale
    When "Priya" turns two-factor off while the app runs in Japanese
    Then "Priya" is emailed "Two-factor authentication was turned off for your account" dated "Dec 08, 2026"

  # ── Error cases ───────────────────────────────────────────────────────────────

  # X11 — Error case: a wrong password is refused and counted toward the lock
  @rack_test @stub-whatsapp @two_factor_cache
  Scenario: X11 Wrong password
    Given "Priya" is signed in on the website
    And I enter the WhatsApp OTP to verify
    When I submit the turn-off popup with password "wrong-password" and the code "123456"
    Then I should see "The password you entered is incorrect."
    And "Priya" has two-factor on with the "whatsapp" method
    And "Priya" has 1 failed password attempt recorded

  # X12 — Error case: a wrong code is refused, with the attempts left
  @rack_test @two_factor_cache
  Scenario: X12 Wrong code
    Given "Dev" is signed in on the website with their code
    When I submit the turn-off popup with password "password" and the code "000000"
    Then I should see "The code you entered is incorrect. 2 attempt(s) remaining."
    And "Dev" has two-factor on with the "authenticator" method
    And "Dev" has 1 wrong turn-off codes counted

  # X13 — Error case: the third wrong code in 10 minutes is refused, and so is a correct code 2 minutes later
  @rack_test @two_factor_cache
  Scenario: X13 Third wrong code within 10 minutes
    Given "Dev" is signed in on the website with their code
    And "Dev" has 2 wrong turn-off codes in the last 10 minutes
    When I submit the turn-off popup with password "password" and the code "000000"
    Then I should see "Too many incorrect codes. Try again in 10 minutes."
    When 2 minutes pass
    And I submit the turn-off popup with password "password" and the current code
    Then I should see "Too many incorrect codes. Try again in 10 minutes."
    And "Dev" has two-factor on with the "authenticator" method

  # X14 — Error case: the sixth wrong password locks the account, and the next page is the sign-in page
  @rack_test @stub-whatsapp @two_factor_cache
  Scenario: X14 Six wrong passwords lock the account
    Given "Priya" is signed in on the website
    And I enter the WhatsApp OTP to verify
    And "Priya" already has 5 wrong passwords counted
    When I submit the turn-off popup with password "wrong-password" and the code "123456"
    Then "Priya" is locked
    And I should see "Your account is locked."
    And "Priya" has two-factor on with the "whatsapp" method
