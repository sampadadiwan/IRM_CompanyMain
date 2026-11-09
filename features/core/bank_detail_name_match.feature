@bank_detail_change
Feature: The bank check's name rule for KYCs (OWASP review 2026-11 M14 — §6)
  For a firm with bank verification on, a bank check that finds the account marks Bank Verified when the provider
  reports a name match, or when every word of one name matches a word (or the initial) of the other with at least
  one full word in common — ignoring titles, punctuation and company-suffix spellings. Anything else is left for a
  person: Bank Verified stays off with "Name needs review: the bank has '<name>'". A check's result is applied only
  if the account and IFSC are still the ones it checked. Secondary-sale offers keep today's rule.
  Kestrel Capital has bank verification on; Dev Menon makes the changes.
  Worked examples H12–H14, E47–E56, X13–X14:
  openspec/changes/bank-detail-change-controls/business-rules.md#6-bank-check-name-rule--phase-4

  # H12 — Happy path: the bank says "ANIL SHARMA" with the provider's own match → Bank Verified ✓
  Scenario: H12 The provider's match is accepted
    Given the KYC "Anil Sharma" is unverified
    And the bank check returns "ANIL SHARMA" with a provider match
    When "Dev" saves the KYC "Anil Sharma" with:
      | account | 60200012121212 |
    Then the KYC "Anil Sharma" has Bank Verified on

  # H13 — Happy path: "THIMMAIAH C" for "Thimmaiah Chengappa", no provider match → ✓ (the initial matches)
  Scenario: H13 An initial matches the full word
    Given the KYC "Thimmaiah Chengappa" is unverified
    And the bank check returns "THIMMAIAH C" without a provider match
    When "Dev" saves the KYC "Thimmaiah Chengappa" with:
      | account | 60200013131313 |
    Then the KYC "Thimmaiah Chengappa" has Bank Verified on

  # H14 — Happy path: "ABC PVT LTD" for "ABC Private Limited" → ✓ (company suffixes)
  Scenario: H14 Company suffixes are the same name
    Given the KYC "ABC Private Limited" is unverified
    And the bank check returns "ABC PVT LTD" without a provider match
    When "Dev" saves the KYC "ABC Private Limited" with:
      | account | 60200014141414 |
    Then the KYC "ABC Private Limited" has Bank Verified on

  # E47 — Edge case: "R KUMAR" for "A Kumar" → off; "Name needs review: the bank has 'R KUMAR'"
  Scenario: E47 A look-alike initial goes to review
    Given the KYC "A Kumar" is unverified
    And the bank check returns "R KUMAR" without a provider match
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200015151515 |
    Then the KYC "A Kumar" has Bank Verified off
    And the KYC "A Kumar" keeps its bank check status "Name needs review: the bank has 'R KUMAR'"

  # E48 — Edge case: "KUMAR" (surname only) for "A Kumar" → off; Name needs review
  Scenario: E48 A surname alone goes to review
    Given the KYC "A Kumar" is unverified
    And the bank check returns "KUMAR" without a provider match
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200016161616 |
    Then the KYC "A Kumar" has Bank Verified off
    And the KYC "A Kumar" keeps its bank check status "Name needs review: the bank has 'KUMAR'"

  # E49 — Edge case: "MR A KUMAR" for "A Kumar" → ✓ (the title is ignored)
  Scenario: E49 A title is ignored
    Given the KYC "A Kumar" is unverified
    And the bank check returns "MR A KUMAR" without a provider match
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200017171717 |
    Then the KYC "A Kumar" has Bank Verified on

  # E50 — Edge case: "ANIL KUMAR SHARMA" for "Anil Sharma" → ✓ (every KYC word is in the bank name)
  Scenario: E50 An extra middle name at the bank
    Given the KYC "Anil Sharma" is unverified
    And the bank check returns "ANIL KUMAR SHARMA" without a provider match
    When "Dev" saves the KYC "Anil Sharma" with:
      | account | 60200018181818 |
    Then the KYC "Anil Sharma" has Bank Verified on

  # E51 — Edge case: "RAMESH SHARMA" for "Anil Sharma" → Name needs review
  Scenario: E51 A different first name goes to review
    Given the KYC "Anil Sharma" is unverified
    And the bank check returns "RAMESH SHARMA" without a provider match
    When "Dev" saves the KYC "Anil Sharma" with:
      | account | 60200019191919 |
    Then the KYC "Anil Sharma" has Bank Verified off
    And the KYC "Anil Sharma" keeps its bank check status "Name needs review: the bank has 'RAMESH SHARMA'"

  # E52 — Edge case: "SHARMA ANIL" for "Anil Sharma" → ✓ (word order swapped)
  Scenario: E52 The word order is swapped
    Given the KYC "Anil Sharma" is unverified
    And the bank check returns "SHARMA ANIL" without a provider match
    When "Dev" saves the KYC "Anil Sharma" with:
      | account | 60200020202020 |
    Then the KYC "Anil Sharma" has Bank Verified on

  # E53 — Edge case: the check of …7310 is still running when Dev saves …9902; the first result is dropped and the
  # …9902 check decides
  Scenario: E53 A stale check result is discarded
    Given the KYC "A Kumar" is unverified
    And the bank check of the account ending "7310" matches but takes so long that "Dev" saves "60200000009902" meanwhile
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200000007310 |
    Then the KYC "A Kumar" has "account" "60200000009902"
    And the KYC "A Kumar" has Bank Verified off
    When the bank check of the KYC "A Kumar" runs again and returns "R KUMAR" without a provider match
    Then the KYC "A Kumar" has Bank Verified off
    And the KYC "A Kumar" keeps its bank check status "Name needs review: the bank has 'R KUMAR'"

  # E54 — Edge case: Horizon (checks off) — Meera changes Anil's account → no provider call; Bank Verified stays off
  Scenario: E54 With checks off no bank check runs
    Given the KYC "Anil Kumar" is unverified
    And the bank check must not be called
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then the KYC "Anil Kumar" has Bank Verified off

  # E55 — Edge case: a Kestrel secondary-sale offer by "A Kumar"; the bank says "R KUMAR" → bank verified as today
  Scenario: E55 A secondary-sale offer keeps today's name rule
    Given the bank check returns "R KUMAR" without a provider match
    And a Kestrel secondary-sale offer by "A Kumar" with bank details
    When the bank check of that offer runs
    Then that offer is bank verified

  # E56 — Edge case: after E47, Asha checks the cheque and ticks Bank Verified → ✓; Dev cannot tick it
  Scenario: E56 A second approver accepts a name under review
    Given the KYC "A Kumar" is unverified
    And the bank check returns "R KUMAR" without a provider match
    And "Dev" saves the KYC "A Kumar" with:
      | account | 60200015151515 |
    When "Dev" opens the edit page of the KYC "A Kumar"
    Then the edit page has no Bank Verified box
    When "Asha" saves the KYC "A Kumar" with:
      | Bank Verified | 1 |
    Then the KYC "A Kumar" has Bank Verified on

  # X13 — Error case: the bank cannot find the account ("Invalid account") → off; status "Invalid account" as today
  Scenario: X13 The account is not found
    Given the KYC "A Kumar" is unverified
    And the bank check finds no account and says "Invalid account"
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200021212121 |
    Then the KYC "A Kumar" has Bank Verified off
    And the KYC "A Kumar" keeps its bank check status "Invalid account"

  # X14 — Error case: the provider answers with a body that is not JSON → off; the raw body kept; no error page
  Scenario: X14 An unreadable provider answer
    Given the KYC "A Kumar" is unverified
    And the bank check answers "<html>Bad Gateway</html>"
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200022222222 |
    Then the KYC "A Kumar" has Bank Verified off
    And the KYC "A Kumar" has the bank check response "Bad Gateway"
    And "Dev" is told "Investor kyc was successfully saved."
