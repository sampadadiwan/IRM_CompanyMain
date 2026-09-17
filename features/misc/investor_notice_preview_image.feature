Feature: Investor notice card doesn't show a broken image when there's nothing to show
  As an LP viewing the dashboard carousel
  I want a notice card to render cleanly when it has no image link and its
  GP has no logo uploaded
  So that I never see a broken-image icon

  # _preview.html.erb falls back from investor_notice.link to entity.logo;
  # when neither is present it used to render <img src=""> anyway (a broken
  # image icon). Now the whole image column is skipped and the content column
  # takes the full row instead.

  Scenario: A notice with no image link and no entity logo renders without a broken image
    Given there is an entity "name=No Logo GP;entity_type=Investment Fund;enable_funds=true"
    Given there is an investor "No Logo LP" with an approved login
    Given there is an entity-wide investor notice titled "No Image Notice" with generate enabled
    When the investor notice job runs for "No Image Notice"
    And I login as investor "No Logo LP"
    And I visit the investor dashboard
    Then I should see the investor notice "No Image Notice"
    And the notices carousel should not show a broken image
