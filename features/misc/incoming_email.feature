@notification
Feature: Incoming Email
  Can receive incoming emails via SendGrid and log them to the DB,
  linking them to the correct owner by address pattern or entity mailbox

  Background:
    Given Im logged in as a user "" for an entity ""
    Given the user has role "company_admin"
    Given there is an existing investor "name=Investor 1"

  # ─── Routing by structured To address ───────────────────────────────────────

  @rack_test
  Scenario: Email addressed to owner system address is linked to that owner
    Given there is an incoming email addressed to this investor from "test@example.com" with subject "Pitch Deck"
    Then the email should be linked to the investor

  # ─── Routing by entity mailbox ───────────────────────────────────────────────

  Scenario: Email to entity mailbox with matching subject links to investor
    Given the entity_setting has "mailbox=incoming@myentity.com"
    Given there is an incoming email sent for this investor "to=incoming@myentity.com;from=sender@example.com;subject=Investor 1"
    Then the email should be "true" to the investor

  Scenario: Email to entity mailbox with non-matching subject creates email without owner
    Given the entity_setting has "mailbox=incoming@myentity.com"
    Given there is an incoming email sent for this investor "to=incoming@myentity.com;from=sender@example.com;subject=Unknown Fund"
    Then the email should be "false" to the investor

  Scenario: Email to entity mailbox matches investor regardless of subject capitalisation
    Given the entity_setting has "mailbox=incoming@myentity.com"
    Given there is an incoming email sent for this investor "to=incoming@myentity.com;from=sender@example.com;subject=investor 1"
    Then the email should be "true" to the investor

  # ─── Attachments ─────────────────────────────────────────────────────────────

  @rack_test
  Scenario: Email with attachment saves the document against the email
    Given there is an incoming email addressed to this investor from "test@example.com" with subject "Pitch Deck" and attachment "investors.xlsx"
    Then the email should be linked to the investor
    And the email should have 1 document attached

  # ─── Idempotency ─────────────────────────────────────────────────────────────

  @rack_test
  Scenario: Sending the same email twice via SendGrid does not create duplicates
    Given there is an incoming email addressed to this investor from "test@example.com" with subject "Duplicate Test" and message id "<msg-001@example.com>"
    And the same SendGrid payload is submitted again
    Then only 1 incoming email record should exist with subject "Duplicate Test"
