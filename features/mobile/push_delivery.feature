# LP mobile app — push notifications (design cards ⑤ ⑥). Expo is stubbed (@expo-push).
# Worked examples: openspec/changes/lp-mobile-app/design.md#worked-examples
@cross-region-cache @expo-push
Feature: LP mobile app push notifications
  Every investor notification can also arrive on the phone, but only where its email would go,
  never to the fund manager's own staff, and only in the categories the investor left on.

  Background:
    Given a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"
    And Arka Growth Fund I is set up for Sharma Family Office
    And "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    And the phone "iPhone 15" registered the push address "ExponentPushToken[iphone15]"

  # H10 — Happy path: allowing notifications registers the phone's push address
  Scenario: Register a push address
    Then the phone "iPhone 15" is marked "ok" for push

  # H11 — Happy path: a capital call notice is pushed once to each of the investor's phones
  Scenario: Capital call pushed to both phones
    Given "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    And the phone "Pixel 8" registered the push address "ExponentPushToken[pixel8]"
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 2 pushes were sent
    And the push address "ExponentPushToken[iphone15]" got 1 push
    And the push address "ExponentPushToken[pixel8]" got 1 push
    And each push is titled "Arka Capital" and opens Capital Call 3

  # H12 — Happy path: the fund manager's custom subject is the push text
  Scenario: Custom subject used
    Given Arka Capital customised the capital call subject to "Arka Growth I — Call 3 notice"
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then the push body is "Arka Growth I — Call 3 notice"

  # E7 — Edge case: a phone handed to another user stops getting the previous user's pushes
  Scenario: Same phone, new user
    Given a mobile investor "vikram@kapoor.in" of "Kapoor Holdings" with fund manager "Arka Capital"
    And "vikram@kapoor.in" is signed in on the phone "Shared Pixel"
    And the phone "Shared Pixel" registered the push address "ExponentPushToken[iphone15]"
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 0 pushes were sent
    And the phone "iPhone 15" has no push address

  # E9 — Edge case: email switched off for the investor access means no push either
  Scenario: Email disabled means no push
    Given Rahul's investor access to Arka Capital has email switched off
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 0 pushes were sent
    And "rahul@sharmafo.in" still has the notification in their alerts

  # E10 — Edge case: a category switched off stops its pushes, nothing else
  Scenario: Category switched off
    Given "rahul@sharmafo.in" switched off "capital_calls" push notifications
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 0 pushes were sent
    And "rahul@sharmafo.in" still has the notification in their alerts

  # E11 — Edge case: the fund manager's own staff are never pushed
  Scenario: Internal notification not pushed
    Given "meera@arkacapital.in" is an employee of the fund manager "Arka Capital"
    And "meera@arkacapital.in" is signed in on the phone "Meera's iPhone"
    And the phone "Meera's iPhone" registered the push address "ExponentPushToken[meera]"
    When Arka Capital sends the Capital Call 3 notice to "meera@arkacapital.in"
    Then 0 pushes were sent

  # E12 — Edge case: a notifier with no category falls into "Everything else"
  Scenario: Unmapped notifier type
    Then a notification of type "SomeNewNotifier" is in the push category "other"
    And a notification of type "CapitalDistributionPaymentNotifier" is in the push category "distributions"

  # E13 — Edge case: someone the email would not reach is not pushed
  Scenario: No email, no push for a user without access to the record
    Given a mobile investor "vikram@kapoor.in" of "Kapoor Holdings" with fund manager "Arka Capital"
    And "vikram@kapoor.in" is signed in on the phone "Vikram's Pixel"
    And the phone "Vikram's Pixel" registered the push address "ExponentPushToken[vikram]"
    And Vikram's investor access to Arka Capital has email switched off
    When Arka Capital sends the Capital Call 3 notice to "vikram@kapoor.in"
    Then 0 pushes were sent

  # E14 — Edge case: a long subject is cut to fit a lock screen
  Scenario: Long subject truncated
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in" with a 250-character subject
    Then the push body is 178 characters ending with "..."

  # E26 — Edge case: a phone with push switched off is skipped
  Scenario: Phone push switched off
    Given "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    And the phone "Pixel 8" registered the push address "ExponentPushToken[pixel8]"
    When the phone "Pixel 8" sends "PUT" to "/api/mobile/v1/device" with:
      """
      { "push_enabled": false }
      """
    And Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then the push address "ExponentPushToken[iphone15]" got 1 push
    And the push address "ExponentPushToken[pixel8]" got 0 pushes

  # E27 — Edge case: a signed-out phone is not pushed
  Scenario: Signed-out phone not pushed
    Given "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    And the phone "Pixel 8" registered the push address "ExponentPushToken[pixel8]"
    And the phone "iPhone 15" was signed out on the website
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 1 push was sent
    And the push address "ExponentPushToken[pixel8]" got 1 push

  # E35 — Edge case: a retried push job does not push the same phone twice
  Scenario: Retried job does not double-push
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    And the push job for that notification runs again
    Then 1 push was sent

  # X10 — Error case: Expo says the address is dead — stop pushing to it
  Scenario: Reinstalled app
    Given Expo's receipt will report "DeviceNotRegistered" for the push address "ExponentPushToken[iphone15]"
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    And the push receipts are checked 16 minutes later
    Then the phone "iPhone 15" is marked "not_registered" for push
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 1 push was sent

  # X10 — Error case (immediate ticket error): the same, reported straight away
  Scenario: Dead address reported on send
    Given Expo will report "DeviceNotRegistered" for the push address "ExponentPushToken[iphone15]"
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then the phone "iPhone 15" is marked "not_registered" for push

  # X11 — Error case: Expo down — the push job fails to be retried; the notification still exists
  Scenario: Expo is down
    Given Expo is down
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then the push job failed with a retryable error
    And "rahul@sharmafo.in" still has the notification in their alerts

  # X20 — Error case: no Expo token in this region — push is simply not attempted
  Scenario: Push not configured
    Given push is not configured in this region
    When Arka Capital sends the Capital Call 3 notice to "rahul@sharmafo.in"
    Then 0 pushes were sent
    And "rahul@sharmafo.in" still has the notification in their alerts
