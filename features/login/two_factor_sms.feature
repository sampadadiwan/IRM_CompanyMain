@stub-twilio
Feature: Two-Factor Authentication by SMS
  SMS is the third delivery mode alongside WhatsApp and authenticator apps. It is offered
  only when the deployment has it switched on and the user's stored number can actually
  be texted — there is no per-user opt-in column, the number itself is the entitlement.
  See docs/technical/twilio_sms_otp_design.md.

  Background:
    Given there is a user "" for an entity "entity_type=Company"
    And the user has two-factor authentication enabled but not configured

  # ── Eligibility ─────────────────────────────────────────────────────────────

  Scenario: SMS is offered when the user has a textable mobile number
    Given the user has the phone number "+1" "4155550134"
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should see the SMS mode option

  # The destination allowlist that used to gate this was removed: a US-deployment account
  # holding an Indian mobile is ordinary, and refusing it showed the user no SMS option
  # with nothing on screen to explain why. Twilio Geo Permissions is now the only bound
  # on where we dial. See SmsDeliverable.
  Scenario: A foreign mobile number is offered SMS on the US deployment
    Given this is the US deployment
    And the user has the phone number "91" "9449025878"
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should see the SMS mode option
    When I select the SMS mode
    Then I should be on the SMS 2FA enrollment page
    And a text message should have been sent to "+919449025878"

  Scenario Outline: SMS is hidden when the number cannot be texted
    Given the user has the phone number "<call_code>" "<phone>"
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should not see the SMS mode option

    Examples: reasons a number is unusable
      | call_code | phone      | why                                   |
      |           |            | no number stored at all               |
      | 1         | 12345      | not a valid number                    |
      | 1         | 9449025878 | Indian number carrying a US call code |
      | 44        | 7700900123 | reserved range, not assignable        |
      | 91        | 8028319623 | a landline cannot receive SMS         |

  Scenario: SMS is hidden when the deployment has the feature switched off
    Given the user has the phone number "+1" "4155550134"
    And SMS two-factor is switched off for this deployment
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should not see the SMS mode option

  # ── Enrollment ──────────────────────────────────────────────────────────────

  Scenario: User enrols via SMS
    Given the user has the phone number "+1" "4155550134"
    And I am at the login page
    When I fill and submit the login page
    And I select the SMS mode
    Then I should be on the SMS 2FA enrollment page
    And a text message should have been sent to "+14155550134"
    When I enter the texted code to confirm enrollment
    Then I should see "Two-factor authentication via text message is now enabled"
    And the user should have 2FA enabled in sms mode
    And the user should have no backup codes

  Scenario: Wrong code during SMS enrollment
    Given the user has the phone number "+1" "4155550134"
    And I am at the login page
    When I fill and submit the login page
    And I select the SMS mode
    Then I should be on the SMS 2FA enrollment page
    When I enter an invalid TOTP code and confirm
    Then I should see "Invalid code"
    And the user's two-factor setup should not be complete

  Scenario: Choosing SMS is refused server-side when the number is unusable
    # The mode-selection screen never offers SMS to this user, but the POST is
    # unauthenticated and the body is attacker-controlled, so the server re-checks.
    Given the user has the phone number "44" "7700900123"
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    When I force-submit the SMS mode
    Then I should see "not available for your account"
    And no text message should have been sent

  # ── Login ───────────────────────────────────────────────────────────────────

  Scenario: Signing in with SMS sends a code automatically
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And a text message should have been sent to "+14155550134"
    When I enter the texted code
    Then I should be signed in

  Scenario: Signing in by magic link also challenges for the SMS code
    # The mode dispatch used to be duplicated between password login and magic link,
    # and had already drifted once. This proves both entry points behave the same.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    When I sign in using a magic link
    Then I should be on the 2FA verification page
    And a text message should have been sent to "+14155550134"

  Scenario: Three wrong codes returns the user to sign-in
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code 3 times
    Then I should be redirected to the login page

  # ── Cost and abuse controls ─────────────────────────────────────────────────

  Scenario: A second send to the same number inside a minute is refused
    # The per-number limit is what actually stops toll fraud: an attacker points many
    # accounts at one payout number, and each account looks well-behaved alone.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And I am at the login page
    When I fill and submit the login page
    Then exactly 1 text message should have been sent
    When the rate limit is exhausted for that number
    And the code is sent again
    Then exactly 1 text message should have been sent
    And the delivery should be recorded as failed with "rate_limited"

  Scenario: A refused send still counts as an attempt
    # Counting successes rather than attempts would make a number that reliably
    # errors free to hammer.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And the next text message will fail with Twilio code 60200
    When the code is sent
    Then no text message should have been sent
    And the delivery should be recorded as failed with "60200"
    And the attempt should have been counted against that number

  Scenario: Permanent Twilio failures are not retried
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And the next text message will fail with Twilio code 60200
    When the code is sent
    Then the job should not have raised

  # ── Regressions from code review ────────────────────────────────────────────

  Scenario: The kill switch stops sends for already-enrolled users
    # The switch is documented as the one-step stop for a runaway bill. Guarding only
    # sms_available? meant every enrolled user's login kept spending after it was thrown.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And SMS two-factor is switched off for this deployment
    And I am at the login page
    When I submit the login page expecting to be refused
    Then no text message should have been sent
    And I should see "contact your administrator"

  Scenario: A user whose number stops being textable is told, not stranded
    # Otherwise the verification screen says "Code texted to …" and offers a code box for
    # a message that was never sent — and SMS mode has no backup codes.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And an administrator changes the number to "44" "7700900123"
    And I am at the login page
    When I submit the login page expecting to be refused
    Then no text message should have been sent
    And I should see "contact your administrator"

  Scenario: Enrollment page does not send a fresh code on every load
    Given the user has the phone number "+1" "4155550134"
    And I am at the login page
    When I fill and submit the login page
    And I select the SMS mode
    Then exactly 1 text message should have been sent
    When I reload the enrollment page
    Then exactly 1 text message should have been sent

  Scenario: Concurrent sends cannot both pass the one-per-minute cap
    # Check-then-act let two racing sends each read a count under the limit.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    When the code is sent twice concurrently
    Then exactly 1 text message should have been sent

  # ── Verify-specific: which system checks the code ───────────────────────────

  Scenario: A wrong code is rejected and the verification stays open
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then I should see "Invalid code"
    When I enter the texted code
    Then I should be signed in

  Scenario: Authenticator-mode user does not see a text fallback button
    # App-only is the deliberate policy once a user has chosen the authenticator app:
    # the WhatsApp/SMS fallback buttons are not offered on the login screen at all.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And I should not see "Text me a code"

  Scenario: Verify is not consulted when no code was texted
    # Probing Verify after a failed TOTP entry would burn attempts on a verification the
    # user never had. An authenticator user, who has no way to request a text, must not
    # trigger a single check call.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then no verification check should have been made

  Scenario: Verify routing does not depend on the session hint alone
    # The real bug: session[:otp_user_id] was present but the channel hint was not, so a
    # correct Verify code was checked against the TOTP secret and rejected as invalid.
    #
    # This asserts the durable conditions the routing now falls back on. It cannot strip
    # a single key from an encrypted session cookie through the browser, so it proves the
    # fallback INPUTS are present rather than simulating the loss itself.
    Given the user has the phone number "+1" "4155550134"
    And the user has two-factor authentication enabled in sms mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And the code routing should not need the session hint
    When I enter the texted code
    Then I should be signed in

  # ── Number normalisation ────────────────────────────────────────────────────

  Scenario Outline: Stored formats all resolve to one dialable number
    # Hashing the raw stored string instead of the normalised one would let the
    # per-number rate limit be defeated by re-saving in a different format.
    Given the user has the phone number "<call_code>" "<phone>"
    Then the user's SMS number should normalise to "+14155550134"

    Examples:
      | call_code | phone            |
      | 1         | 4155550134       |
      | 1         | (415) 555-0134   |
      | 1         | 415-555-0134     |
      | +1        | 415 555 0134     |
      | 1         | +14155550134     |
