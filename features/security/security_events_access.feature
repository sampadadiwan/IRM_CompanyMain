@security @rack_test
Feature: Security event trail — roles, support access, credentials and exports (OWASP 2026-11 M11)
  Who got power, and what left the building: every role granted or removed by any route, the "Enable support"
  switch, CapHive support signing in as a client or switching into a firm, API keys, phones and connected apps,
  and every spreadsheet, folder, report and firm data download. Each is one append-only event naming the account,
  who did it and the firm. Nothing the person sees changes.
  Design: openspec/changes/archive/2026-11-10-security-event-trail (business-rules.md §3, §4, §7 — H16–H27, E23–E32, E47, E48,
  X1, X2).

  Background:
    Given the security cast "Rahul, Meera, Priya, Karan"

  # ── §3 Access and support ───────────────────────────────────────────────────

  # H16 — Happy path: an admin ticking Approver on themselves records role.granted; account and Done by are both them
  Scenario: H16 Self-grant approver
    When "Rahul" saves the roles of "Rahul" as "company_admin, approver"
    Then a security event "role.granted" is recorded for "Rahul" with:
      | role    | approver           |
      | done by | Rahul              |
      | firm    | Golden Angels Fund |
      | door    | web_password       |

  # H17 — Happy path: another admin unticking it records role.revoked, Done by that admin
  Scenario: H17 Revoke approver
    Given "Rahul" holds the role "approver"
    When "Meera" saves the roles of "Rahul" as "company_admin"
    Then a security event "role.revoked" is recorded for "Rahul" with:
      | role    | approver |
      | done by | Meera    |
    And no security event "role.granted" is recorded

  # H18 — Happy path: turning on Enable support records support_access.enabled from false to true
  Scenario: H18 Support switch on
    Given "Rahul" has Enable support switched off
    When "Rahul" turns on Enable support on their own profile
    Then a security event "support_access.enabled" is recorded for "Rahul" with:
      | from | false |
      | to   | true  |

  # H19 — Happy path: CapHive support using Login as records support.signed_in_as — Done by support, firm of the client
  Scenario: H19 Support Login as
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" uses Login as on "Priya"
    Then a security event "support.signed_in_as" is recorded for "Priya" with:
      | done by      | Anil               |
      | on behalf of | Anil               |
      | firm         | Golden Angels Fund |
      | via          | login_as           |

  # H20 — Happy path: the support user signing out ends the support session — recorded for the client's firm
  Scenario: H20 Support session ends
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" uses Login as on "Priya"
    And "Anil" signs out of the website
    Then a security event "support.session_ended" is recorded for "Priya" with:
      | firm         | Golden Angels Fund |
      | on behalf of | Anil               |

  # H21 — Happy path: a support user switching into a firm and back records both, for the client's firm
  Scenario: H21 Firm switch and back
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" switches into "Golden Angels Fund" and back
    Then a security event "support.firm_switched" is recorded for "Anil" with:
      | firm | Golden Angels Fund |
    And a security event "support.switched_back" is recorded for "Anil" with:
      | firm | Golden Angels Fund |

  # E23 — Edge case: a user import granting employee records role.granted, door system, Done by the importer
  Scenario: E23 Employee role granted by an import
    When an import run by "Rahul" creates the employee "neel@golden-angels-fund.test" in "Golden Angels Fund"
    Then a security event "role.granted" is recorded for "neel@golden-angels-fund.test" with:
      | role    | employee |
      | door    | system   |
      | done by | Rahul    |

  # E24 — Edge case: a grant inside a transaction that rolls back records nothing
  Scenario: E24 Rolled-back grant
    When a grant of "approver" to "Karan" is rolled back
    Then no security event is recorded

  # E25 — Edge case: saving a user's roles unchanged removes nothing that was not held, so nothing is recorded
  Scenario: E25 Removing a role not held
    When "Rahul" saves the roles of "Karan" as "employee"
    Then no security event "role.granted" is recorded
    And no security event "role.revoked" is recorded

  # E26 — Edge case: an approved investor access that creates the LP user records role.granted investor
  Scenario: E26 Investor role via investor access
    When an investor access for "lena@lenafo.test" is approved in "Golden Angels Fund"
    Then a security event "role.granted" is recorded for "lena@lenafo.test" with:
      | role | investor |

  # E27 — Edge case: support switched off for every user at once is one system event with no firm
  Scenario: E27 Support off for everyone
    Given "Rahul", "Meera" and "Karan" have Enable support switched on
    When support is switched off for everyone
    Then exactly 1 security event "support_access.disabled" is recorded
    And a security event "support_access.disabled" is recorded with:
      | door    | system |
      | firm    | none   |
      | account | none   |
      | scope   | all    |

  # E28 — Edge case: what support does while signed in as the client carries the support user as On behalf of
  Scenario: E28 Actions while impersonating
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil", signed in as "Priya", changes her phone to end in "77"
    Then a security event "phone.changed" is recorded for "Priya" with:
      | on behalf of | Anil |
      | to           | **77 |

  # E29 — Edge case: support signing in through a client's sign-in link is support access, not a client sign-in
  Scenario: E29 Support via a sign-in link
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" opens the sign-in link of "Karan" as support
    Then a security event "support.signed_in_as" is recorded for "Karan" with:
      | done by | Anil       |
      | via     | magic_link |
    And no security event "sign_in.succeeded" is recorded for "Karan"

  # X1 — Error case: Login as refused (no mapping) shows the same refusal as before and records no support access
  Scenario: X1 Login as refused
    Given the security cast "Anil"
    When "Anil" uses Login as on "Priya"
    Then "Anil" sees "Access Denied"
    And no security event "support.signed_in_as" is recorded

  # ── §4 Credentials and exports ──────────────────────────────────────────────

  # H22 — Happy path: an API key created records its name; the token string is nowhere in the row
  Scenario: H22 API key created
    When "Rahul" creates the API key "Zapier sync"
    Then a security event "api_token.created" is recorded for "Rahul" with:
      | name | Zapier sync |
    And no security event holds a secret

  # H23 — Happy path: revoking the key records api_token.revoked with its name
  Scenario: H23 API key revoked
    When "Rahul" creates the API key "Zapier sync"
    And "Rahul" revokes the API key "Zapier sync"
    Then a security event "api_token.revoked" is recorded for "Rahul" with:
      | name | Zapier sync |

  # H24 — Happy path: a phone signed out from the website records mobile_device.revoked, reason website_sign_out
  Scenario: H24 Mobile device revoked
    When "Priya" signs the phone "Priya's iPhone" out from the website
    Then a security event "mobile_device.revoked" is recorded for "Priya" with:
      | name   | Priya's iPhone   |
      | reason | website_sign_out |

  # H25 — Happy path: approving a connected app on the consent screen records its name and scopes
  Scenario: H25 Connected app authorised
    When "Rahul" authorises the connected app "Claude"
    Then a security event "connected_app.authorised" is recorded for "Rahul" with:
      | app    | Claude |
      | scopes | read   |
      | door   | oauth  |

  # H26 — Happy path: a spreadsheet download records data.exported naming the screen
  Scenario: H26 Spreadsheet download
    When "Rahul" downloads "/capital_calls.xlsx" as a spreadsheet
    Then the request of "Rahul" is answered with 200
    And a security event "data.exported" is recorded for "Rahul" with:
      | what | capital_calls#index (xlsx) |

  # H27 — Happy path: a folder download records data.exported with the folder's name
  Scenario: H27 Folder download
    When "Rahul" downloads the folder "Quarterly reports"
    Then a security event "data.exported" is recorded for "Rahul" with:
      | what | folders#download  |
      | name | Quarterly reports |

  # E30 — Edge case: a refused spreadsheet is refused as before and records nothing
  Scenario: E30 Refused spreadsheet
    When "Priya" downloads "/doc_checks.xlsx" as a spreadsheet
    Then "Priya" sees "Access Denied"
    And no security event "data.exported" is recorded

  # E31 — Edge case: a firm data dump records data.exported for that firm
  Scenario: E31 Firm data dump
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" asks for a data dump of "Golden Angels Fund"
    Then a security event "data.exported" is recorded with:
      | what    | entity_db_dump     |
      | firm    | Golden Angels Fund |
      | done by | Anil               |

  # E32 — Edge case: downloading the Audit Trail is itself recorded
  Scenario: E32 Audit download
    When "Rahul" downloads "/audits.xlsx" as a spreadsheet
    Then a security event "data.exported" is recorded for "Rahul" with:
      | what | audits#index (xlsx) |

  # X2 — Error case: the 11th live key is refused as before; nothing is recorded
  Scenario: X2 Eleventh live key refused
    Given "Rahul" already has 10 live API keys
    When "Rahul" creates the API key "One more"
    Then "Rahul" sees "You already have 10 live tokens — revoke one first"
    And no security event "api_token.created" is recorded

  # ── §7 Never affects the user ───────────────────────────────────────────────

  # E47 — Edge case: the role save message is exactly as before
  Scenario: E47 Role save message unchanged
    When "Rahul" saves the roles of "Rahul" as "company_admin, approver"
    Then "Rahul" sees "User was successfully updated."

  # E48 — Edge case: the Login as message is exactly as before
  Scenario: E48 Login as message unchanged
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" uses Login as on "Priya"
    Then "Anil" sees "Signed in as Priya Shah"
