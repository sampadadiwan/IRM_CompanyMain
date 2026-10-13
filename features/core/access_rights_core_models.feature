@access_rights_core_models @rack_test
Feature: Core model access rights

  Covers the six core-pack models: Investor, InvestorKyc, Document, Folder,
  Valuation, and Task.  These models use ApplicationPolicy helpers rather than
  the fund-based AR chain.

  Background:
    # Pin entity_type to prevent non-deterministic role assignment in setup_defaults
    Given there is an entity "name=Fund Entity;entity_type=Investment Fund"
    And there is a user "email=admin@example.com" for the entity "name=Fund Entity"
    And the user "admin@example.com" has role "company_admin"
    And there is a user "email=employee@example.com" for the entity "name=Fund Entity"
    And the user "employee@example.com" has role "employee"
    # Investor firm + investor user for cross-entity access checks
    And there is an entity "name=Investor Firm;entity_type=Investor"
    And there is a user "email=investor@example.com" for the entity "name=Investor Firm"
    And the user "investor@example.com" has role "investor"
    # Unrelated entity for negative (cross-entity) checks
    And there is an entity "name=Other Entity;entity_type=Investment Fund"
    And there is a user "email=outsider@example.com" for the entity "name=Other Entity"
    And the user "outsider@example.com" has role "employee"

  # ===========================================================================
  # INVESTOR
  # InvestorPolicy.show?: enable_investors && (entity_id == investor_entity_id ||
  #                        specific_permissions?(:investor_read))
  # ===========================================================================

  Scenario: Company admin can show an investor in their entity
    # Company admin path: extended_permissioned_employee? short-circuits to true
    Given there is an investor "investor_name=LP Alpha" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    Then the user "admin@example.com" should be allowed "show" on the investor record

  Scenario: User from the investor entity can show that investor
    # show? checks user.entity_id == record.investor_entity_id
    Given there is an investor "investor_name=LP Beta" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    Then the user "investor@example.com" should be allowed "show" on the investor record

  Scenario: User from an unrelated entity is denied show on an investor
    Given there is an investor "investor_name=LP Gamma" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    Then the user "outsider@example.com" should be denied "show" on the investor record

  # ===========================================================================
  # INVESTORKYC
  # InvestorKycPolicy.show?: permissioned_employee?(:investor_kyc_read) ||
  #                          user.entity_id == record.investor.investor_entity_id
  # ===========================================================================

  Scenario: Company admin can show an investor KYC for their entity
    Given there is an investor "investor_name=KYC LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    And there is a kyc for investor "KYC LP"
    Then the user "admin@example.com" should be allowed "show" on the kyc record

  Scenario: Investor user from the investor entity can show their own KYC
    # show? falls through to user.entity_id == record.investor.investor_entity_id
    Given there is an investor "investor_name=KYC LP2" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    And there is a kyc for investor "KYC LP2"
    Then the user "investor@example.com" should be allowed "show" on the kyc record

  Scenario: User from unrelated entity is denied show on a KYC
    Given there is an investor "investor_name=KYC LP3" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    And there is a kyc for investor "KYC LP3"
    Then the user "outsider@example.com" should be denied "show" on the kyc record

  # ===========================================================================
  # DOCUMENT
  # DocumentPolicy.show?: public_visibility || (enable_documents && belongs_to_entity? &&
  #                        (company_admin? || owner_policy.show?)) || show_investor? || ...
  # ===========================================================================

  Scenario: Company admin can show a document in their entity
    Given there is a folder "name=Reports" for the entity "name=Fund Entity"
    And there is a document in the folder "name=Reports"
    Then the user "admin@example.com" should be allowed "show" on the document record

  Scenario: User from unrelated entity is denied show on a document
    Given there is a folder "name=Reports" for the entity "name=Fund Entity"
    And there is a document in the folder "name=Reports"
    Then the user "outsider@example.com" should be denied "show" on the document record

  Scenario: Public document is visible to anyone
    Given there is a folder "name=Public Docs" for the entity "name=Fund Entity"
    And there is a public document in the folder "name=Public Docs"
    Then the user "outsider@example.com" should be allowed "show" on the document record

  # ===========================================================================
  # FOLDER
  # FolderPolicy.show?:
  #   investor_advisor: belongs_to_entity? && owner && owner_policy.show?
  #   others:           belongs_to_entity?
  # ===========================================================================

  Scenario: Employee can show a folder in their entity
    Given there is a folder "name=Finance" for the entity "name=Fund Entity"
    Then the user "employee@example.com" should be allowed "show" on the folder record

  Scenario: User from unrelated entity is denied show on a folder
    Given there is a folder "name=Finance2" for the entity "name=Fund Entity"
    Then the user "outsider@example.com" should be denied "show" on the folder record

  Scenario: Employee can create a folder in their entity
    Given there is a folder "name=New Folder" for the entity "name=Fund Entity"
    Then the user "employee@example.com" should be allowed "create" on the folder record

  Scenario: User from unrelated entity is denied create on a folder
    Given there is a folder "name=New Folder 2" for the entity "name=Fund Entity"
    Then the user "outsider@example.com" should be denied "create" on the folder record

  Scenario: System folder cannot be updated
    Given there is a system folder "name=System Docs" for the entity "name=Fund Entity"
    Then the user "admin@example.com" should be denied "update" on the folder record

  # ===========================================================================
  # VALUATION
  # ValuationPolicy.show?: belongs_to_entity? || (owner && owner_policy.show?)
  # create?/update?: belongs_to_entity? && owner_policy.update?
  # ===========================================================================

  Scenario: Employee can show a valuation in their entity
    Given there is a fund "name=Val Fund" for the entity "name=Fund Entity"
    And there is a valuation for the fund
    Then the user "employee@example.com" should be allowed "show" on the valuation record

  Scenario: User from unrelated entity is denied show on a valuation
    Given there is a fund "name=Val Fund 2" for the entity "name=Fund Entity"
    And there is a valuation for the fund
    Then the user "outsider@example.com" should be denied "show" on the valuation record

  # ===========================================================================
  # TASK
  # TaskPolicy.show?: create? && for_support == false
  # create?:          permissioned_employee?(:create) || user.entity_id == record.for_entity_id
  # ===========================================================================

  Scenario: Employee can show a task assigned to them
    Given there is a task for the entity "name=Fund Entity" assigned to "employee@example.com"
    Then the user "employee@example.com" should be allowed "show" on the task record

  Scenario: User from unrelated entity cannot show a task (for_entity_id mismatch)
    Given there is a task for the entity "name=Fund Entity" assigned to "employee@example.com"
    Then the user "outsider@example.com" should be denied "show" on the task record

  Scenario: Company admin can show any task in their entity
    Given there is a task for the entity "name=Fund Entity" assigned to "employee@example.com"
    Then the user "admin@example.com" should be allowed "show" on the task record

  Scenario: Investor advisor is denied task index
    # TaskPolicy.index? returns false for investor_advisor? users
    # entity_type must be "Investor Advisor" so setup_defaults sets advisor_entity_id,
    # which is what user.investor_advisor? checks (not the role).
    Given there is an entity "name=Advisor Firm;entity_type=Investor Advisor"
    And there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And there is a task for the entity "name=Fund Entity" assigned to "employee@example.com"
    Then the user "advisor@example.com" should be denied "index" on the task record
