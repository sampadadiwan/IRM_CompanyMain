@user_guides
Feature: User guide drift guard
  As a fund manager reading a user guide or asking the Customer Support Agent a "how to" question
  I want every navigation path, cross-link and FAQ entry in docs/user_guides to stay valid
  So that the guides and the agent never point me at a page, guide or answer that no longer exists

  # H14 (capital-call-journey) — the Capital Calls guide's journey sections (all 11 Full and 4
  # Light tasks) are prose, so these link and FAQ rules are the only automated guard on them:
  # openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  Scenario: Guides link to app pages instead of showing raw paths readers would have to type
    When the user guides are linted
    Then no user guide should show a raw app path in backticks

  Scenario: Every guide-to-guide link points at an existing guide
    When the user guides are linted
    Then every relative link in the user guides should point to an existing guide

  Scenario: Every FAQ question is directly followed by its answer so it renders as an accordion entry
    When the user guides are linted
    Then every FAQ question in the user guides should be directly followed by its answer

  Scenario: Every FAQ answer fits inside the support agent's search window
    When the user guides are linted
    Then no FAQ answer in the user guides should exceed 5 lines

  Scenario: Every FAQ entry renders as an accordion item on the in-app guide page
    When the user guides are linted
    Then every FAQ entry in the user guides should render as an accordion item
