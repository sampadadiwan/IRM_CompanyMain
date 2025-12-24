# IRM Cucumber Testing Context

This document serves as a comprehensive guide for AI to write new Cucumber tests for the IRM project. It outlines common steps, test strategies, and architectural patterns used in the existing test suite.

## Core Test Strategy

1.  **Scenario Outlines:** Use `Scenario Outline` with `Examples` to test multiple configurations (e.g., different entity types, currencies, or call bases) in a single scenario.
2.  **FactoryBot & Data Initialization:** Leverage `FactoryBot` for object creation. Most Given steps take a string of key-value pairs (e.g., `Given there is a fund "name=Test;currency=INR"`) which are parsed and applied to the factory-built object using the `key_values` helper.
3.  **Entity-Centric Flow:** Most tests start with logging in as a user for a specific entity type (Investment Fund, Company, etc.).
4.  **Actionable Steps:** Steps are designed to be high-level but map directly to UI actions or background jobs (e.g., `When I create a new capital call`, `Given the units are generated`).
5.  **Exhaustive Verification:** Verify results through:
    *   **UI Checks:** `expect(page).to have_content(...)`
    *   **Database Checks:** `Fund.last.name.should == @fund.name`
    *   **Email Verification:** `open_email(@user.email)`, `expect(current_email.subject).to include(...)`
    *   **Job Execution:** Manually trigger jobs in tests to simulate asynchronous processing: `ImportUploadJob.perform_now(ImportUpload.last.id)`.

## Common Step Definitions

### 1. Authentication & Setup
*   `Given Im logged in as a user {string} for an entity {string}`
    *   Example: `Given Im logged in as a user "first_name=Admin" for an entity "entity_type=Investment Fund;enable_funds=true"`
*   `Given the user has role {string}`
    *   Roles: `company_admin`, `approver`, `investor`, `support`.
*   `Given there is an existing investor {string} with {string} users`
    *   Initializes an investor and creates associated `InvestorAccess` records.

### 2. Fund Management
*   `Given there is a fund {string} for the entity`
    *   Initializes a `Fund` record.
*   `Given the investors are added to the fund`
    *   Grants `AccessRight` to all entity investors for the current `@fund`.
*   `Given there are capital commitments of {string} from each investor`
    *   Creates `CapitalCommitment` records for all fund investors.
*   `When I create a new capital call {string}`
    *   Inputs: `percentage_called`, `call_basis` ("Percentage of Commitment", "Investable Capital Percentage", "Upload").

### 3. Imports & Files
*   `Given Given import file {string} for {string}`
    *   Handles common imports like `CapitalCommitment`, `AccountEntry`, `InvestorKyc`.
    *   Path: Files are expected in `public/sample_uploads/`.
*   `Given Given I upload an investors file for the fund`
    *   Specialized step for importing stakeholders.

### 4. Documents & E-Signatures
*   `Given the fund has capital call template` / `Given the fund has capital commitment template`
    *   Uploads a `.docx` file as a template for document generation.
*   `When the capital call docs are generated`
    *   Triggers background generation of customized PDFs for each remittance.
*   `Then the generated doc must be attached to the capital remittances`
*   `Then the document is signed by the signatories`
    *   Used in conjunction with Digio or Docusign stubs.

### 5. Investor & KYC
*   `Given each investor has a "verified" kyc linked to the commitment`
*   `When I navigate to the new individual KYC page`
*   `Then I should see ckyc and kra data comparison page` (Used for Indian regulatory KYC flows).

### 6. Verification & Utility
*   `Then I should see the {string}`
*   `And the remittance rollups should be correct`
    *   Exhaustive check of financial sums across Fund, Commitment, and Remittance levels.
*   `Then the investors must receive email with subject {string}`
*   `Then sleep {string}` (Use sparingly).

## Key Domain Logic Patterns

### Key-Value Parsing
Most setup steps use a pattern like `key_values(@object, arg_string)`.
*   Example string: `"name=Urban;entity_type=Investment Fund;enable_funds=true"`
*   This automatically sets attributes on the Ruby object before saving.

### Financial Assertions
Tests frequently assert amounts in cents:
`@fund.committed_amount_cents.should == CapitalCommitment.sum(:committed_amount_cents)`

### Handling Multi-Tenancy / Entity Types
The system behaves differently based on `entity_type`:
*   `Investment Fund`: Focuses on Funds, Calls, Distributions, Units.
*   `Company`: Focuses on Deals, Investors, KPIs.

## Example Scenario Structure

```gherkin
Scenario Outline: Comprehensive Fund Flow
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  And there is a fund "name=Alpha Fund;currency=USD" for the entity
  And Given import file "stakeholders.xlsx" for "Investor"
  And Given import file "commitments.xlsx" for "CapitalCommitment"
  When I create a new capital call "percentage_called=10"
  Then the corresponding remittances should be created
  And when the capital call is approved
  And I mark the remittances as paid
  And I mark the remittances as verified
  Then the capital call collected amount should be "<expected_amount>"
  And the units are generated
  Then there should be correct units for the calls payment for each investor

  Examples:
    | expected_amount |
    | 1000000         |
```

## Directory Structure
*   `features/*.feature`: High-level business requirements.
*   `features/step_definitions/*.rb`: Ruby implementation of steps.
*   `features/support/env.rb`: Capybara/Cucumber configuration and helpers.
*   `public/sample_uploads/`: Excel/PDF/Docx files used for import tests.
