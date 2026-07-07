@notification
Feature: Access Right Notification
  Granting a user direct access to a resource (AccessRight#user_id present) can send
  them a notification email, via AccessRight#send_notification -> AccessRightNotifier
  -> AccessRightsMailer#send_notification.

  Background:
    Given there is a user "email=owner@example.com" for an entity "name=Test Entity;entity_type=Investment Fund"
    Given there is a user "email=grantee@example.com" for the entity "name=Test Entity"
    Given there is a fund "name=SAAS Fund" for the entity

  Scenario: User receives a notification email when granted direct access with notify enabled
    When the user "grantee@example.com" is granted access to the fund with notify enabled
    Then the user "grantee@example.com" receives an access granted notification email for the fund

  Scenario: User does not receive a notification email when notify is not enabled
    When the user "grantee@example.com" is granted access to the fund without notify enabled
    Then the user "grantee@example.com" does not receive an access granted notification email

  Scenario: Investor's user receives a notification email when granted access via access_to_investor_id with notify enabled
    Given there is an existing investor "" with "1" users
    When the investor is granted access to the fund with notify enabled
    Then the investor's user receives an access granted notification email for the fund

  Scenario: Investor's user does not receive a notification email when notify is not enabled
    Given there is an existing investor "" with "1" users
    When the investor is granted access to the fund without notify enabled
    Then the investor's user does not receive an access granted notification email

  Scenario: Investor's user receives a notification email when granted access via access_to_category with notify enabled
    Given there is an existing investor "category=VIP" with "1" users
    When investors in category "VIP" are granted access to the fund with notify enabled
    Then the investor's user receives an access granted notification email naming their own entity
