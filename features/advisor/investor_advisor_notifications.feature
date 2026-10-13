Feature: Investor Advisor notification recipients
  Whether an investor advisor receives a notification must not depend on which host entity he
  happens to be switched into when somebody else presses Send — and fixing that must not let
  him receive anything he could not already see after reverting to his home entity.

  Production shape: the advisor is the only approved contact on his OWN investor record (the
  record sits in his home entity), the KYC document's only access right is investor-scoped, and
  he is currently switched into an unrelated client entity that granted him extra roles.

  Background:
    Given Im logged in as a user "first_name=Dhairav" for an entity "name=Shroff Family Office;entity_type=Investor Advisor"
    And the user has role "investor_advisor"
    And the advisor's home persona roles are "investor,investor_advisor"
    And there is a fund company "name=ACF;entity_type=Investment Fund" with a fund "name=ACF XII"
    And the advisor is the sole approved contact on an investor record of the fund company for his own home entity
    And the investor has a KYC with an approved document that grants access to the investor
    And the advisor has switched into an unrelated host entity that granted him roles "company_admin,approver"

  @security @rack_test
  Scenario: NOTIF-1 A switched-away advisor still receives documents for his own investor record
    # The reported bug: "No users to send the document" because the recipient check was judged
    # against the entity the advisor was switched into rather than the one owning his record.
    Then the advisor is a notification recipient for the KYC document
    And sending the KYC document succeeds and is delivered to the advisor
    And the advisor's persisted entity and roles are unchanged by the recipient check

  @security @rack_test
  Scenario: NOTIF-2 Recipients while switched away are exactly the recipients after a real revert
    # The privilege bound: the fix may only reproduce what InvestorAdvisor.revert would yield.
    When I record the notification recipients for the KYC document while switched
    And I revert to my home entity
    Then I am back in my original entity
    And the notification recipients for the KYC document after reverting are the same set
    And a user who is not switched away has no home persona

  @security @rack_test
  Scenario: NOTIF-3 Roles borrowed from the host entity do not leak into the home persona
    Then my roles should include "company_admin"
    And my roles should include "approver"
    And the home persona of the advisor carries only his home entity and home roles

  @security @rack_test
  Scenario: NOTIF-4 A document visible only through borrowed roles is not sent
    # Hybrid state (home entity_id + host roles) would pass DocumentPolicy#show? via
    # company_admin. The recipient check must not take that path.
    Given there is an unapproved generated document in the advisor's home entity that only a company admin there could see
    Then the switched-in roles combined with the home entity would expose that document
    But the advisor is not a notification recipient for that document

  @security @rack_test
  Scenario: NOTIF-6 The KYC form and reminder recipient path is bounded the same way
    # InvestorKyc#notification_users applies its own across_all_entities filter, which has the
    # same blind spot for the advisor's own record; it now shares the home-persona rule.
    Then the advisor is a recipient of the KYC form notification
    When I record the KYC form recipients while switched
    And I revert to my home entity
    Then the KYC form recipients after reverting are the same set

  @security @rack_test
  Scenario: NOTIF-7 Following a notification link while switched away says how to get access
    # Authorization for show is unchanged: the switched-in persona is still denied. The denial
    # explains the persona switch only when the home persona could see the record.
    When I visit the KYC document while switched into the host entity
    Then I am told to switch my persona back to view it
    Given there is an unapproved generated document in the advisor's home entity that only a company admin there could see
    When I visit that hidden document
    Then I am simply denied access

  @security @rack_test
  Scenario: NOTIF-8 The persona hint escapes the host entity name
    # layouts/_alerts renders flashes html_safe and the entity name is admin-editable.
    Given the host entity is renamed to "Client <b>Bold</b> & Co"
    When I visit the KYC document while switched into the host entity
    Then I am told to switch my persona back to view it
    And the host entity name is shown escaped, not rendered as markup

  @security @rack_test
  Scenario: NOTIF-9 The home persona holds investor_advisor exactly when a real revert would
    # An admin can store advisor_entity_roles without investor_advisor; revert's setup_defaults
    # forces it back for an "Investor Advisor" home entity, so the persona must match that.
    Given the stored home persona roles are changed to "investor"
    Then the home persona roles equal the roles after a real revert

  @security
  Scenario: NOTIF-5 Advising another client's investor record while switched away is unaffected
    # The home-entity check is limited to the advisor's own investor records; for a client's
    # record the existing rules apply unchanged and the home persona is never consulted.
    Given the advisor is also an approved contact on another client's investor record with a KYC document
    Then the advisor is not a notification recipient for the client's document and his home persona is not consulted
