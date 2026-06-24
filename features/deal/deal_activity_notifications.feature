@notification
Feature: Deal Activity Move Notifications
  As a deal manager
  I want to receive notifications when a deal moves to a new stage
  And I want to be able to customize these notifications per deal and per stage

  Background:
    Given there is a startup entity
    And there is a user for the entity
    And I am logged in
    And there exists a deal "name=Series B" for company
    And the deal is started and has an investor "Global VC"
    And the deal has enable notifications set

  @javascript
  Scenario: Standard notification when a deal moves to a new stage
    Given the deal activity "Financial DD" has "notify_employees" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then an email should be sent to the current user with subject "Deal Update: Series B moved to stage: Financial DD"

  @javascript
  Scenario: Custom notification for a specific stage using tags
    Given there is a custom notification for the deal with method "deal_activity_move" and tag "Financial DD" and subject "Custom DD Subject"
    And the deal activity "Financial DD" has "notify_employees" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then an email should be sent to the current user with subject "Custom DD Subject"

  @javascript
  Scenario: Fallback custom notification for the deal
    Given there is a custom notification for the deal with method "deal_activity_move" and subject "Generic Deal Move"
    And the deal activity "Financial DD" has "notify_employees" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then an email should be sent to the current user with subject "Generic Deal Move"

  @javascript
  Scenario: Notification to investor when a deal moves to a new stage
    Given the investor "Global VC" has an approved user "investor@vc.com"
    And the deal activity "Financial DD" has "notify_investor" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then a deal notification email should be sent to "investor@vc.com" with subject "Deal Update: Series B moved to stage: Financial DD"

  @javascript
  Scenario: Tag-matching investor contact receives deal activity notification
    Given the investor "Global VC" has an approved user "investor@vc.com" with tag_list "Deal"
    And the deal activity "Financial DD" has "notify_investor" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then a deal notification email should be sent to "investor@vc.com" with subject "Deal Update: Series B moved to stage: Financial DD"

  @javascript
  Scenario: Non-matching tag excludes investor contact from deal activity notification
    Given the investor "Global VC" has an approved user "investor@vc.com" with tag_list "KYC"
    And the deal activity "Financial DD" has "notify_investor" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then no deal notification email should be sent to "investor@vc.com"

  @javascript
  Scenario: Custom notification placeholders are resolved for deal activity move
    Given there is a custom notification with placeholders for the deal with method "deal_activity_move" and subject "Deal Placeholder Test"
    And the deal activity "Financial DD" has "notify_employees" enabled
    When I move the deal investor "Global VC" to stage "Financial DD"
    Then the deal notification placeholders are resolved correctly
