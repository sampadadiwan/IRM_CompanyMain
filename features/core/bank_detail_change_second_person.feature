@bank_detail_change
Feature: A second person verifies a bank change (OWASP review 2026-11 M14 — §5)
  While a bank change waits for a second person, the person who made it cannot verify the KYC — on the page (Verify
  greyed out, with the reason), in bulk or by an import row — nor tick Bank Verified. Any other KYC approver
  verifies through a popup that says what happens, and that records them as the confirmer. A change made by the
  investor or by System can be confirmed by any approver. A firm with no other approver who can see the KYC lets its
  only approver verify after a warning card, recorded as "only approver". UnVerify stays open to everyone allowed.
  Worked examples H9–H11, E32–E46:
  openspec/changes/bank-detail-change-controls/business-rules.md#5-second-person--phase-3

  # H9 — Happy path: Meera's change awaits; Ravi clicks Verify, reads the cards, clicks "Verify KYC" → verified;
  # the note reads "Confirmed by Ravi Iyer on 10/11/2026"
  Scenario: H9 The second approver verifies through the popup
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
      | IFSC    | ICIC0004567    |
    And the next day comes
    When "Ravi" confirms the Verify popup of the KYC "Anil Kumar"
    Then "Ravi" is told "Investor kyc was successfully verified."
    And the KYC "Anil Kumar" is verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status        | confirmed |
      | confirmed by  | Ravi Iyer |
      | only approver | no        |
    And the bank change note says "Confirmed by Ravi Iyer on 10/11/2026"

  # H10 — Happy path: Anil (investor) changed his own account; Meera verifies → verified, confirmed by Meera
  Scenario: H10 Any approver confirms an investor's own change
    Given the KYC "Anil Kumar" was sent to the investor
    And the investor "anil.kumar@example.in" submits the KYC "Anil Kumar" through the emailed link with:
      | account | 50100273107310 |
    And the KYC "Anil Kumar" is unverified
    When "Meera" confirms the Verify popup of the KYC "Anil Kumar"
    Then the KYC "Anil Kumar" is verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status       | confirmed  |
      | confirmed by | Meera Shah |

  # H11 — Happy path: Solo Advisors; Kiran (the only approver) changes Leela's account after UnVerify and clicks
  # Verify → the only-approver card; confirm → verified, recorded "only approver"
  Scenario: H11 The only approver verifies their own change after the warning card
    Given the KYC "Leela Menon" is unverified
    And "Kiran" saves the KYC "Leela Menon" with:
      | account | 70300099887766 |
    When "Kiran" opens the KYC "Leela Menon"
    Then the Verify popup shows the card "You are the only KYC approver" saying "You are the only KYC approver at Solo Advisors — this is recorded as confirmed by the person who made the change."
    When "Kiran" confirms the Verify popup of the KYC "Leela Menon"
    Then the KYC "Leela Menon" is verified
    And the latest bank change of the KYC "Leela Menon" is:
      | status        | confirmed |
      | confirmed by  | Kiran Rao |
      | only approver | yes       |

  # E32 — Edge case: Meera opens the KYC she changed → Verify greyed out with the reason as its tooltip
  Scenario: E32 The maker's Verify is greyed out
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" opens the KYC "Anil Kumar"
    Then the page shows Verify greyed out saying "You changed this KYC's bank details. Another KYC approver must verify it."
    And the page has no Verify popup

  # E33 — Edge case: Ravi clicks Verify → cards "New payout account confirmed" (••••7310, ICIC0004567),
  # "You are the second person" (Meera Shah, 09/11/2026), "Investor already told" (anil.kumar@example.in)
  Scenario: E33 The popup's cards say what happens
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
      | IFSC    | ICIC0004567    |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the Verify button opens the popup "Verify KYC — Anil Kumar"
    And the Verify popup shows the card "New payout account confirmed" saying "••••7310 (IFSC ICIC0004567)"
    And the Verify popup shows the card "You are the second person" saying "Meera Shah made this change on 09/11/2026"
    And the Verify popup shows the card "Investor already told" saying "anil.kumar@example.in was emailed on 09/11/2026"
    And the Verify popup has no card "Bank check"
    And the Verify popup has the buttons "Cancel" and "Verify KYC"

  # E34 — Edge case: Kestrel; Dev changed "A Kumar"'s account; the check said "Name needs review: the bank has 'R KUMAR'"
  # → Asha's popup has an extra card "Bank check: Name needs review"
  Scenario: E34 The popup shows a bank check that has not passed
    Given the KYC "A Kumar" is unverified
    And the bank check returns "R KUMAR" without a provider match
    And "Dev" saves the KYC "A Kumar" with:
      | account | 60200099990000 |
    When "Asha" opens the KYC "A Kumar"
    Then the Verify popup shows the card "Bank check: Name needs review" saying "R KUMAR"

  # E35 — Edge case: Bina's KYC unverified, no change → Ravi's Verify verifies at once, as today (no popup)
  Scenario: E35 No awaiting change, no popup
    Given the KYC "Bina Shah" is unverified
    When "Ravi" opens the KYC "Bina Shah"
    Then the page has no Verify popup
    When "Ravi" verifies the KYC "Bina Shah" from its page
    Then "Ravi" is told "Investor kyc was successfully verified."
    And the KYC "Bina Shah" is verified

  # E36 — Edge case: Anil's KYC verified, no change → Meera clicks UnVerify → unverified as today
  Scenario: E36 The maker can still UnVerify
    Given the KYC "Anil Kumar" is already verified
    When "Meera" unverifies the KYC "Anil Kumar" from its page
    Then "Meera" is told "Investor kyc was successfully unverified."
    And the KYC "Anil Kumar" is not verified

  # E37 — Edge case: Meera's change awaits on Anil; Bina and Chetan unverified (Chetan with full details) → Meera
  # bulk-verifies the three → Bina and Chetan verified; Anil listed with the maker message
  Scenario: E37 Bulk Verify by the maker skips her own change
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    And the KYC "Bina Shah" is unverified
    And the KYC "Chetan Rao" has full bank details
    When "Meera" bulk-verifies the KYCs "Anil Kumar, Bina Shah, Chetan Rao"
    Then the KYC "Bina Shah" is verified
    And the KYC "Chetan Rao" is verified
    And the KYC "Anil Kumar" is not verified
    And the bulk result lists "Anil Kumar" as "Not verified — you changed the bank details; another approver must verify"

  # E38 — Edge case: Kiran's change on Leela awaits; Solo adds Uma (Approve) before Kiran verifies → Kiran greyed;
  # Uma can verify
  Scenario: E38 A second approver added later blocks the maker again
    Given the KYC "Leela Menon" is unverified
    And "Kiran" saves the KYC "Leela Menon" with:
      | account | 70300099887766 |
    And the person "Uma" exists
    When "Kiran" opens the KYC "Leela Menon"
    Then the page shows Verify greyed out saying "Another KYC approver must verify it."
    When "Uma" confirms the Verify popup of the KYC "Leela Menon"
    Then the KYC "Leela Menon" is verified

  # E39 — Edge case: Horizon with Meera + Kabir (Approve, cannot see Anil's KYC); Ravi deactivated → Meera changes
  # then clicks Verify → the only-approver card; confirm → recorded "only approver"
  Scenario: E39 An approver who cannot see the KYC does not count
    Given the KYC "Anil Kumar" is unverified
    And the person "Kabir" exists
    And the user "Ravi" is no longer active
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" opens the KYC "Anil Kumar"
    Then the Verify popup shows the card "You are the only KYC approver" saying "You are the only KYC approver at Horizon Capital"
    When "Meera" confirms the Verify popup of the KYC "Anil Kumar"
    Then the KYC "Anil Kumar" is verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | confirmed by  | Meera Shah |
      | only approver | yes        |

  # E40 — Edge case: Anil verified; Meera imports Update Only: new account, Verified Yes → "Success with warnings";
  # unverified; awaiting
  Scenario: E40 An import with Verified = Yes and a bank change leaves the KYC unverified
    Given the KYC "Anil Kumar" is already verified
    When "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Bank Account Number | 50100273107310 |
      | Verified            | Yes            |
    Then the import row says "Success with warnings" with "Bank details changed — the KYC was left unverified for another approver to verify"
    And the KYC "Anil Kumar" is not verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status | awaiting   |
      | maker  | Meera Shah |
      | source | import     |

  # E41 — Edge case: after E40 Meera imports the same row again (no further change), Verified Yes → same warning;
  # still unverified
  Scenario: E41 The maker's later import cannot verify
    Given the KYC "Anil Kumar" is already verified
    And "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Bank Account Number | 50100273107310 |
      | Verified            | Yes            |
    When "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Verified | Yes |
    Then the import row says "Success with warnings" with "Bank details changed — the KYC was left unverified for another approver to verify"
    And the KYC "Anil Kumar" is not verified

  # E42 — Edge case: after E40 Ravi imports the row, Verified Yes → "Success"; verified; confirmed by Ravi
  Scenario: E42 The second person's import confirms
    Given the KYC "Anil Kumar" is already verified
    And "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Bank Account Number | 50100273107310 |
      | Verified            | Yes            |
    When "Ravi" imports an Update Only row for the KYC "Anil Kumar" with:
      | Verified | Yes |
    Then the import row says "Success"
    And the KYC "Anil Kumar" is verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status       | confirmed |
      | confirmed by | Ravi Iyer |

  # E43 — Edge case: Meera imports a new KYC with an account and Verified Yes → verified; no record; no email
  Scenario: E43 A new KYC import is unchanged
    When "Meera" imports a new KYC "Dinesh Pai" for the investor "Dinesh Pai" with:
      | Bank Account Number | 40100011112222 |
      | Ifsc Code           | HDFC0007777    |
      | Verified            | Yes            |
    Then the import row says "Success"
    And the KYC "Dinesh Pai" is verified
    And the KYC "Dinesh Pai" has no bank change
    And no bank change email was sent

  # E44 — Edge case: Meera's change awaits → Meera's Edit has no Bank Verified box; Ravi's has it and saves ✓
  Scenario: E44 The maker cannot tick Bank Verified, the second approver can
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" opens the edit page of the KYC "Anil Kumar"
    Then the edit page has no Bank Verified box
    When "Ravi" opens the edit page of the KYC "Anil Kumar"
    Then the edit page has a Bank Verified box saying "Tick only after checking proof of the current account"
    When "Ravi" saves the KYC "Anil Kumar" with:
      | Bank Verified | 1 |
    Then the KYC "Anil Kumar" has Bank Verified on

  # E45 — Edge case: the AI extraction job (no acting user) changed the account → Meera verifies → confirmed by Meera
  Scenario: E45 A System change is confirmed by any approver
    Given the KYC "Anil Kumar" is unverified
    And the AI extraction writes "50100273107310" to "account" on the KYC "Anil Kumar" with nobody behind it
    When "Meera" confirms the Verify popup of the KYC "Anil Kumar"
    Then the KYC "Anil Kumar" is verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status       | confirmed  |
      | confirmed by | Meera Shah |

  # E46 — Edge case: after H9, Meera UnVerifies then Verifies (no new change) → both work, no popup
  Scenario: E46 After confirmation the maker is free again
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    And "Ravi" confirms the Verify popup of the KYC "Anil Kumar"
    When "Meera" unverifies the KYC "Anil Kumar" from its page
    Then the KYC "Anil Kumar" is not verified
    When "Meera" opens the KYC "Anil Kumar"
    Then the page has no Verify popup
    When "Meera" verifies the KYC "Anil Kumar" from its page
    Then the KYC "Anil Kumar" is verified
