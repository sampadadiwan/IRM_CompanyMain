@notification
Feature: WhatsApp delivery for custom notifications
  The :whats_app deliver_by must only enqueue a WhatsApp send when the owning CustomNotification
  has a populated `whatsapp` field - a blank field (saved as "" by the form, not nil) means the
  notifier itself never enqueues the job at all, with no fallback to the notification's email
  subject/body.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given the investor user has WhatsApp enabled
    Given there is a fund "name=Test fund" for the entity
    And user goes to add a new document "test doc" for the fund
    Then user should be able to save the document
    Given the document notifies the WhatsApp-enabled investor user

  Scenario: A populated whatsapp field is sent as-is
    Given there is a custom notification for the document with subject "Doc ready" and whatsapp "Your document is ready"
    When the document is sent to the investor
    And the document's WhatsApp delivery is attempted
    Then a WhatsApp message "Your document is ready" is sent to the investor

  Scenario: A blank whatsapp field means the notifier never enqueues a WhatsApp delivery
    Given there is a custom notification for the document with subject "Doc ready" and a blank whatsapp field
    When the document is sent to the investor
    Then the notifier does not enqueue a WhatsApp delivery for the investor
