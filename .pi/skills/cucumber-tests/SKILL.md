---
name: cucumber-tests
description: 'Guidelines and workflows for writing Cucumber tests in the IRM project.'
---

# Cucumber Tests Skill

This skill provides a standardized approach to writing Cucumber tests for the IRM project, ensuring consistency, reusability, and good coverage across both UI and business logic.

## Key Principles

1.  **Reuse Existing Steps**: Before creating new steps, check `features/common.rb` for general-purpose steps.
2.  **Tagging Strategy**:
    *   `@javascript`: Required for UI tests that need a real browser (Capybara).
    *   `@unit`: Use for fast tests that verify business logic or service objects directly (no UI).
    *   `@smoke`: Critical path scenarios.
    *   `@slow`: For long-running scenarios.
3.  **Scenario Outlines**: Prefer `Scenario Outline` with `Examples` tables for testing multiple data variations.
4.  **Role-Based Testing**: Ensure users are created with the correct roles using established steps.
5.  **Data Isolation**: Use `FactoryBot` (inside steps) to set up the necessary state.

## Core Step Reference (`features/common.rb`)

Use these common steps for setup and basic interaction:

- **User & Entity Creation**:
  - `Given there is a user "email=user@example.com,name=John" for an entity "name=Acme Corp"`
  - `Given there is a user "email=admin@test.com" for an existing entity "name=Acme Corp"`
  - *Note: These use the `key_values` helper to parse the string and apply it to FactoryBot objects.*
- **Role Assignment**:
  - `And the user has role "admin"` (can be comma-separated: `"admin, advisor"`)
  - `And the user has curr role "admin"`
- **Login**:
  - `Given Im a logged in user "email=user@example.com"` (this combines user creation, role assignment, and login)
  - `Given the user is logged in`
- **UI Interaction**:
  - `When I click "Button Name"`
  - `When I click "Save" within ".form-actions"`
  - `Then I should see the "Success message"`
- **Emails**:
  - `Then the user receives an email with "Subject" as the subject`

## UI-Based Testing Example

UI tests should focus on end-to-end user flows.

```gherkin
@javascript @smoke
Feature: Document Management
  Background:
    Given there is a user "email=admin@example.com" for an entity "name=LPs"
    And the user has role "admin"
    And Im a logged in user "email=admin@example.com"

  Scenario Outline: Uploading various document types
    When I click "Documents"
    And I upload a file with type "<type>"
    Then I should see the message "Document <name> uploaded successfully"

    Examples:
      | type | name          |
      | pdf  | report.pdf    |
      | xlsx | quarterly.xlsx|
```

## Unit/Logic Testing Example

Use Cucumber to test model logic or services directly. These tests are fast as they don't use a browser.

```gherkin
@unit
Feature: Support Client Mapping Logic
  Background:
    Given a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the user to the entity

  Scenario: Enable support permission logic
    When I enable the mapping
    Then the mapping should be enabled
    And the entity should have enable_support permission
    And all employees should have enable_support set to true
```

## Workflow for Adding Tests

1.  **Identify the Pack**: Locate the relevant pack in `app/packs/[domain]/`.
2.  **Create/Edit Feature File**: Add your `.feature` file to `features/[domain]/`.
3.  **Implement Steps**:
    - Place new step definitions in `features/step_definitions/[domain]_steps.rb`.
    - Always prefer using `FactoryBot` over manual database insertion.
4.  **Verification**:
    - Run the specific feature: `bundle exec cucumber features/[domain]/my_feature.feature`
    - Check for linting: `bundle exec rubocop features/step_definitions/[domain]_steps.rb`
