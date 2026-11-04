Feature: Security C5 - a stakeholder's linked firm, and the users a merge moves
  A stakeholder's linked firm (investor_entity_id) decides which portal users are its contacts. The
  stakeholder form no longer accepts it, and a merge re-homes the old firm's users only when both
  linked firms are LP firms that no other GP knows. Paired scenarios prove the legitimate paths -
  the email-change relink, the support admin panel and the Entity merge - still work.
  Design: docs/security/security_review_2026_10.md, card "C5 — Stakeholder linked firm + merge"

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select" for the entity
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"

  # C5-1 — Error case: a posted linked firm is ignored, the rest of the edit is saved
  @security @rack_test
  Scenario: C5-1 Updating a stakeholder with another firm's id leaves its link unchanged
    Given there is an LP "Harshal" of my fund
    When I update the LP "Harshal" with the linked firm of "Zeta Capital" and city "Pune"
    Then the LP "Harshal" is still linked to its own firm and has city "Pune"

  # C5-2 — Edge case: the OLD side's linked firm is shared with another GP
  @security @rack_test
  Scenario: C5-2 Merging from a firm another GP also knows leaves its users in place
    Given there is an LP "Old LP" of my fund
    And there is an LP "New LP" of my fund
    And the LP "Old LP" has a contact "lata@oldlp.example"
    And the firm of LP "Old LP" is also a stakeholder of "Zeta Capital"
    And in-app alerts are captured
    When I merge the LP "Old LP" into "New LP"
    Then the contact "lata@oldlp.example" still belongs to the firm of "Old LP"
    And the grant of contact "lata@oldlp.example" is now on the LP "New LP"
    And the merge alert warns "1 contacts not moved — ask CapHive support to merge the entities"

  # C5-3 — Edge case: the NEW side's linked firm is shared with another GP
  @security @rack_test
  Scenario: C5-3 Merging into a firm another GP also knows leaves the users in place
    Given there is an LP "Old LP" of my fund
    And there is an LP "New LP" of my fund
    And the LP "Old LP" has a contact "lata@oldlp.example"
    And the firm of LP "New LP" is also a stakeholder of "Zeta Capital"
    And in-app alerts are captured
    When I merge the LP "Old LP" into "New LP"
    Then the contact "lata@oldlp.example" still belongs to the firm of "Old LP"
    And the grant of contact "lata@oldlp.example" is now on the LP "New LP"
    And the merge alert warns "1 contacts not moved — ask CapHive support to merge the entities"

  # C5-H — Happy path: both linked firms are private LP firms, so the user follows the merge
  @security @rack_test
  Scenario: C5-H Merging two private LP firms moves the user, who sees the merged commitment
    Given there is an LP "Old LP" of my fund
    And there is an LP "New LP" of my fund
    And the LP "Old LP" has a contact "lata@oldlp.example"
    And the LP "New LP" has a commitment in my fund
    And in-app alerts are captured
    When I merge the LP "Old LP" into "New LP"
    Then the contact "lata@oldlp.example" belongs to the firm of "New LP"
    And the contact "lata@oldlp.example" sees the commitment of "New LP"
    And the merge alert reports success without skipped contacts

  # C5-H2 — Happy path: the email-change relink, which never used the dropped param, still works
  @security @rack_test
  Scenario: C5-H2 Changing a user-less stakeholder's email still relinks its firm
    Given there is an LP "Harshal" of my fund
    When I change the primary email of the LP "Harshal" to "harshal.new@lp.example"
    Then the LP "Harshal" is linked to the firm with email "harshal.new@lp.example"

  # C5-X — Exception: support can still relink a stakeholder in the admin panel, and the cascade runs
  @security @rack_test
  Scenario: C5-X Support relinks a stakeholder in the admin panel
    Given the user has role "support"
    And the support user is mapped to my firm
    And there is an LP "Harshal" of my fund
    And the LP "Harshal" has a contact "lata@harshal.example"
    And there is an LP firm "Harshal Holdings"
    When I relink the LP "Harshal" to the firm "Harshal Holdings" in the admin panel
    Then the LP "Harshal" is linked to the firm "Harshal Holdings" and its grants follow

  # C5-X2 — Exception: the support-only Entity merge still moves users, even from a shared firm
  @security @rack_test
  Scenario: C5-X2 The Entity merge path moves users whatever the firm
    Given there is an LP "Old LP" of my fund
    And there is an LP "New LP" of my fund
    And the LP "Old LP" has a contact "lata@oldlp.example"
    And the firm of LP "Old LP" is also a stakeholder of "Zeta Capital"
    When support runs the Entity merge of the LP "Old LP" into "New LP"
    Then the contact "lata@oldlp.example" belongs to the firm of "New LP"
