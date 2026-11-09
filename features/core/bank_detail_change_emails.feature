@bank_detail_change
Feature: A bank change emails the investor and the firm's approvers, once (OWASP review 2026-11 M14 — §4)
  Each bank change emails, once, the investor's approved contacts subscribed to KYC emails (or to all topics) whose
  access existed before the change — never an address held in the KYC itself — with the last 4 digits only, and
  emails and bell-alerts the firm's KYC approvers who can see the KYC, except the person who made the change. Each
  email says why the person got it and what to do if the change was not expected.
  Worked examples H7, H8, E24–E31, X6:
  openspec/changes/bank-detail-change-controls/business-rules.md#4-change-emails--phase-2

  # H7 — Happy path: Meera changes account + IFSC → anil.kumar@example.in gets the masked email with "View KYC"
  Scenario: H7 The investor is emailed, masked
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
      | IFSC    | ICIC0004567    |
    Then "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"
    And that email says "Nov 09, 2026"
    And that email says "ending 4821 → ending 7310"
    And that email says "HDFC0001234 → ICIC0004567"
    And that email says "Meera Shah"
    And that email says "If you did not ask for this change, contact Horizon Capital straight away"
    And that email says "You are receiving this because you are a contact for the KYC of Anil Kumar"
    And that email has a "View KYC" link to the KYC "Anil Kumar"
    And that email does not say "50100273107310"
    And that email does not say "50100012344821"

  # H8 — Happy path: Ravi gets the approver email + an in-app notification naming anil.kumar@example.in; Meera nothing
  Scenario: H8 The approvers are told, the maker is not
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then "Ravi" receives 1 email "Bank details changed for Anil Kumar — a second approver must verify"
    And that email says "anil.kumar@example.in"
    And that email says "You are receiving this because you are a KYC approver at Horizon Capital"
    And that email says "Meera Shah made the change, so a different KYC approver must verify it"
    And "Ravi" has a bell notification "Bank details changed for Anil Kumar — a second approver must verify"
    And "Meera" receives no bank change email

  # E24 — Edge case: sunita.kumar@example.in is subscribed to Distribution only → not emailed
  Scenario: E24 A contact subscribed to other topics only is not emailed
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"
    And "sunita.kumar@example.in" receives no bank change email

  # E25 — Edge case: change saved at 10:00; a new contact approved at 10:01; the email job runs at 10:02 → not emailed
  Scenario: E25 A contact added after the change is not emailed
    Given the KYC "Anil Kumar" is unverified
    And the bank change emails are held until they are sent
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    And a minute later the contact "new.contact@example.in" is approved for the investor of "Anil Kumar"
    And a minute later the held bank change emails are sent
    Then "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"
    And "new.contact@example.in" receives no bank change email

  # E26 — Edge case: the same save changes the account and the eSign emails to attacker@example.com → not emailed
  Scenario: E26 An address held in the KYC is never used
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account      | 50100273107310       |
      | eSign emails | attacker@example.com |
    Then "attacker@example.com" receives no bank change email
    And "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"

  # E27 — Edge case: H6 (Anil changed it himself) → Anil gets the investor email too ("If you asked for this …")
  Scenario: E27 The investor's own change is emailed to him too
    Given the KYC "Anil Kumar" was sent to the investor
    When the investor "anil.kumar@example.in" submits the KYC "Anil Kumar" through the emailed link with:
      | account | 50100273107310 |
    Then "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"
    And that email says "If you asked for this, no action is needed."
    And "Ravi" receives 1 email "Bank details changed for Anil Kumar — a second approver must verify"

  # E28 — Edge case: H7's job already ran; the same job runs again → still one email per contact and per approver
  Scenario: E28 A retried job sends nothing twice
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When the bank change email job of the KYC "Anil Kumar" runs again
    Then "anil.kumar@example.in" receives 1 email "Your bank details with Horizon Capital were changed"
    And "Ravi" receives 1 email "Bank details changed for Anil Kumar — a second approver must verify"

  # E29 — Edge case: Horizon rewords "notify_bank_details_changed" → Anil's email uses it, masked digits included
  Scenario: E29 The firm rewords the investor email
    Given the KYC "Anil Kumar" is unverified
    And Horizon Capital rewords the bank change email as "Account update at Horizon" with "Dear {{investor_name}}, the payout account changed: {{bank_change_summary}}"
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then "anil.kumar@example.in" receives 1 email "Account update at Horizon"
    And that email says "Dear Anil Kumar, the payout account changed: account ending 4821 → ending 7310"
    And that email does not say "50100273107310"

  # E30 — Edge case: Kabir (Approve, no KYC read, no fund access) cannot see Anil's KYC → not emailed
  Scenario: E30 An approver who cannot see the KYC is not emailed
    Given the KYC "Anil Kumar" is unverified
    And the person "Kabir" exists
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then "Ravi" receives 1 email "Bank details changed for Anil Kumar — a second approver must verify"
    And "Kabir" receives no bank change email

  # E31 — Edge case: Meera changes the branch only → no emails
  Scenario: E31 A branch-only edit sends nothing
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | branch | Indiranagar |
    Then no bank change email was sent

  # X6 — Error case: Anil's investor has no approved contact for KYC emails → no investor email; Ravi's email says so
  Scenario: X6 No investor contact could be emailed
    Given the KYC "Anil Kumar" is unverified
    And the investor of "Anil Kumar" has no contact for KYC emails
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then "anil.kumar@example.in" receives no bank change email
    And "Ravi" receives 1 email "Bank details changed for Anil Kumar — a second approver must verify"
    And that email says "No investor contact could be emailed — confirm the change with the investor by phone."
