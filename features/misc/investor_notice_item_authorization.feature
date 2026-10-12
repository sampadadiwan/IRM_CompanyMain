@rack_test
Feature: Investor notice item authorization
  As the platform
  I want InvestorNoticeItem actions gated by InvestorNoticeItemPolicy, and the
  InvestorNoticeEntry index gated to company admins
  So that a user from one GP cannot read or modify another GP's notice items,
  and only company admins can browse the raw items/entries indexes

  # InvestorNoticeItemsController previously called neither authorize nor
  # policy_scope anywhere, so any authenticated user of any entity could
  # read or mutate any GP's notice items. This feature locks that down.

  Background:
    Given there is an entity "name=Item GP;entity_type=Investment Fund;enable_funds=true"
    Given there is a user "email=admin@itemgp.example.com" for the entity "name=Item GP"
    Given the user "admin@itemgp.example.com" has role "company_admin"
    Given there is a user "email=member@itemgp.example.com" for the entity "name=Item GP"
    Given there is an entity "name=Other GP;entity_type=Investment Fund;enable_funds=true"
    Given there is a user "email=admin@othergp.example.com" for the entity "name=Other GP"
    Given the user "admin@othergp.example.com" has role "company_admin"
    Given there is an investor notice item titled "Deadline reminder" for the entity "name=Item GP"

  Scenario: A user from the owning GP can manage the item
    Then the user "admin@itemgp.example.com" should be allowed "show,create,update,destroy" on the record
    And the user "member@itemgp.example.com" should be allowed "show,create,update,destroy" on the record

  Scenario: A user from a different GP is denied access to the item
    Then the user "admin@othergp.example.com" should be denied "show,create,update,destroy" on the record

  Scenario: Only a company admin may browse the notice items index
    Then the user "admin@itemgp.example.com" should be allowed to list investor notice items
    And the user "member@itemgp.example.com" should be denied to list investor notice items

  Scenario: Only a company admin may browse the notice entries index
    Then the user "admin@itemgp.example.com" should be allowed to list investor notice entries
    And the user "member@itemgp.example.com" should be denied to list investor notice entries
