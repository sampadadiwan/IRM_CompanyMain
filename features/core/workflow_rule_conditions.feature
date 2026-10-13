@rack_test
Feature: Auto-assignment rule conditions — matching
  A rule's conditions may use the record type's search fields, a few rule-only fields (Form type on
  KYCs, Imported on calls) and the company's custom fields. A rule matches a new record when a search
  for its conditions finds that record; amounts compare in currency units, and a condition that cannot
  be applied makes the rule match nothing rather than everything.
  Worked examples H1, H2, H3, H4, E2, E3, E7, E8, X6 in
  openspec/changes/workflow-rule-condition-builder/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are seeded
    And the entity has the KYC form types "Individual — Default, Individual — Fund IV, Non Individual — Default"
    And the "Individual" KYC forms have the custom fields:
      | name          | label         | field_type  | meta_data    |
      | nationality   | Nationality   | Select      | India,USA,UK |
      | ticket_size   | Ticket size   | NumberField |              |
      | passport_copy | Passport copy | File        |              |
    And the template "Investor KYC" is duplicated as "Investor KYC — Fund IV (domestic)"

  # H1 — a form type rule routes only that form type
  Scenario: A form type rule routes only KYCs of that form type
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"<form type: Individual — Fund IV>"}]
      """
    When these KYCs are created:
      | kyc | form type            |
      | A   | Individual — Fund IV |
      | B   | Individual — Default |
    Then they should get the templates:
      | kyc | template                          |
      | A   | Investor KYC — Fund IV (domestic) |
      | B   | Investor KYC                      |

  # H2 — a custom option field routes by value
  Scenario: A custom field rule routes by the KYC's value
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"<form type: Individual — Fund IV>"},
       {"attribute":"json_fields.nationality","operator":"eq","value":"India"}]
      """
    When these KYCs are created:
      | kyc | form type            | nationality |
      | A   | Individual — Fund IV | India       |
      | B   | Individual — Fund IV | USA         |
      | C   | Individual — Fund IV |             |
      | D   | Individual — Default | India       |
    Then they should get the templates:
      | kyc | template                          |
      | A   | Investor KYC — Fund IV (domestic) |
      | B   | Investor KYC                      |
      | C   | Investor KYC                      |
      | D   | Investor KYC                      |

  # E2 — a number custom field compares as a number, not as text ("9" > "10")
  Scenario: A number custom field compares numerically
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"json_fields.ticket_size","operator":"gteq","value":"10"}]
      """
    When these KYCs are created:
      | kyc | form type            | ticket_size |
      | A   | Individual — Fund IV | 9           |
      | B   | Individual — Fund IV | 25          |
    Then they should get the templates:
      | kyc | template                          |
      | A   | Investor KYC                      |
      | B   | Investor KYC — Fund IV (domestic) |

  # E3 — "is blank" takes no value and matches a KYC without the field
  Scenario: A blank condition matches only KYCs without a value
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"json_fields.nationality","operator":"blank"}]
      """
    When these KYCs are created:
      | kyc | form type            | nationality |
      | A   | Individual — Fund IV |             |
      | B   | Individual — Fund IV | India       |
    Then they should get the templates:
      | kyc | template                          |
      | A   | Investor KYC — Fund IV (domestic) |
      | B   | Investor KYC                      |

  # H3 — amounts compare in currency units (committed amount is entered when a commitment is created)
  Scenario: A commitment amount rule compares in currency units
    Given there is a fund "name=Acme Fund IV" for the entity
    And there is a workflow template "name=Commitment — Large" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Commitment — Large" has workflowable_type "CapitalCommitment"
    And a rule on "Commitment — Large" at priority 0 with conditions:
      """
      [{"attribute":"committed_amount","operator":"gteq","value":"5000000"}]
      """
    When these commitments are created:
      | commitment | amount  |
      | Big        | 6000000 |
      | Small      | 2000000 |
    Then they should get the templates:
      | commitment | template           |
      | Big        | Commitment — Large |
      | Small      | none               |

  # H4 — the seeded "Imported" rule still sends imported calls to the Light journey
  Scenario: The seeded imported rule still routes imported calls
    Given there is a fund "name=Acme Fund IV" for the entity
    And the entity's capital call journeys are seeded
    When an imported capital call "percentage_called=10" is created
    Then the call has the "Capital Call — Light: Record Only" journey
    When there is a capital call "percentage_called=10"
    Then the call has the "Capital Call — Full: Notify Investors" journey

  # E7 — rule-only fields do not change list search
  Scenario: A rule-only field is not searchable on list pages
    When these KYCs are created:
      | kyc | form type            |
      | A   | Individual — Fund IV |
      | B   | Individual — Default |
    Then searching the KYC list with "form_type_id_eq" for "Individual — Fund IV" should return every KYC

  # E8 — totals rolled up after creation are always 0 when a rule is checked, so they are not offered;
  # and a list filter another company registered on the class is not one of this company's fields
  Scenario: Rolled-up totals and other companies' list filters are not offered as rule fields
    Given another company's KYC list has registered the filter field "tax_residency" labelled "Tax residency"
    Then the rule fields for "InvestorKyc" should not include "Tax residency"
    And the rule fields for "CapitalCall" should not include "Call amount, Collected amount, Capital fee, Other fee"
    And the rule fields for "CapitalCall" should include "Imported, Percentage called, Fund"
    And the rule fields for "InvestorKyc" should not include "Committed amount, Call amount, PAN, Passport copy"
    And the rule fields for "InvestorKyc" should include "Form type, Verified, Expiry date, Nationality, Ticket size"
    And the rule fields for "CapitalCommitment" should include "Committed amount"

  # X6 — a condition Ransack drops makes the rule match nothing, and is logged
  Scenario: A dropped condition never widens the match
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"kyc_type","operator":"eq","value":"individual"}]
      """
    And Ransack drops the rule's "kyc_type" condition
    And the log is being captured
    When these KYCs are created:
      | kyc | form type            |
      | A   | Individual — Fund IV |
    Then they should get the templates:
      | kyc | template     |
      | A   | Investor KYC |
    And the log should mention "Ransack applied 0 of 1 conditions"
