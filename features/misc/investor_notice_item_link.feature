@rack_test
Feature: InvestorNoticeItem link can reference [user.xxx] variables
  As a GP publishing a notice line item
  I want the item's link to optionally reference the viewing user's own
  attributes (e.g. their entity's subdomain)
  So the same item can deep-link to something specific to each viewer

  # InvestorNoticeLinkInterpolator never calls an arbitrary method or uses
  # eval — only a small allow-list of columns/associations reachable from
  # current_user (never a credential column like otp_secret). Support-only,
  # same gate as InvestorNotice#criteria.

  Background:
    Given there is an entity "name=Link GP;entity_type=Investment Fund;enable_funds=true"
    Given there is an investor "Link LP" with an approved login

  Scenario: A [user.xxx] link resolves per viewer
    Given there is an entity-wide investor notice titled "Dynamic Link Notice" with generate enabled
    And the investor notice "Dynamic Link Notice" has a line item titled "Go to my page" with link "[user.entity.sub_domain]"
    When the investor notice job runs for "Dynamic Link Notice"
    And I login as investor "Link LP"
    And I visit the investor dashboard
    Then the investor notice item "Go to my page" should link to the investor's own entity sub_domain

  Scenario: An unsupported variable is rejected when saving the item
    Given there is an entity-wide investor notice titled "Bad Link Notice" with generate enabled
    Then setting a line item link to "[user.otp_secret]" on the investor notice "Bad Link Notice" should be rejected

  # Checked on the notice's own edit page (fields_for renders one row per
  # existing item) rather than the standalone /investor_notice_items/new
  # page — that page turned out to already be broken before this change
  # (new.html.erb/edit.html.erb render "form" without ever wrapping it in
  # form_with, so `form` is undefined — a pre-existing bug, unrelated to
  # link interpolation, since nothing in the app actually links to that
  # standalone page; items are always created via this nested form).
  Scenario: Only support can set an item's link
    Given there is a user "email=admin@linkgatep.example.com" for the entity "name=Link GP"
    Given the user "admin@linkgatep.example.com" has role "company_admin"
    Given there is a user "email=support2@caphive.example.com" for the entity "name=Link GP"
    Given the user "support2@caphive.example.com" has role "support"
    Given there is an entity-wide investor notice titled "Gated Item Link Notice" with generate enabled
    And the investor notice "Gated Item Link Notice" has a line item titled "Existing Item" with link ""
    When I log in with email "admin@linkgatep.example.com"
    And I visit the edit page for the investor notice "Gated Item Link Notice"
    Then the item link field should not be present
    When I log out
    And I log in with email "support2@caphive.example.com"
    And I visit the edit page for the investor notice "Gated Item Link Notice"
    Then the item link field should be present
