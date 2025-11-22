# IRM Cucumber Testing Guide: A Note to Self

This guide outlines the patterns, reusable steps, and strategies for writing high-quality Cucumber features in the IRM project. Use this as a reference to maintain consistency and maximize step reuse.

---

## 1. Core Strategy & Philosophy

### **The "Golden Flow"**
Most scenarios in IRM follow this sequence:
1.  **Setup**: Log in as a specific user role for a specific entity type.
2.  **Data Initialization**: Create a Fund, Investors, and Commitments using `FactoryBot` and the `key_values` helper.
3.  **Action**: Perform a business operation (e.g., Create a Capital Call, Upload an Import, Approve a Distribution).
4.  **Verification**: Assert UI content, database state, financial rollups (in cents), and email/document generation.

### **Scenario Outlines**
Always prefer `Scenario Outline` with `Examples` for testing multiple configurations (e.g., different currencies, entity types, or call bases) in a single scenario. This ensures broad coverage with minimal duplication.

---

## 2. The `key_values` Power-Tool

The project uses a custom `key_values` helper (defined in `features/support/env.rb`) that allows setting model attributes directly from Gherkin strings.

**Pattern**: `Given there is a [model] "[key1]=[val1];[key2]=[val2]" for the entity`

**Example**:
```gherkin
Given there is a fund "name=Alpha Fund;currency=USD;details=Test Details" for the entity
```

**How it works**:
- It splits the string by `;` and then by `=`.
- It calls `model.send("#{key}=", value)` for each pair.
- For `properties`, it supports nested key-values: `properties=key1:val1,key2:val2`.

---

## 3. Common & Reusable Steps

### **Authentication & Setup**
*   `Given Im logged in as a user {string} for an entity {string}`
    *   *Usage*: `Given Im logged in as a user "first_name=Admin" for an entity "entity_type=Investment Fund;enable_funds=true"`
*   `Given the user has role {string}`
    *   *Roles*: `company_admin`, `approver`, `investor`, `support`.
*   `Given there is an existing investor {string} with {string} users`
    *   *Usage*: `Given there is an existing investor "investor_name=Urban" with "1" users`

### **Fund & Commitment Management**
*   `Given there is a fund {string} for the entity`
*   `Given the investors are added to the fund` (Grants `AccessRight` to all entity investors).
*   `Given there are capital commitments of {string} from each investor`
    *   *Usage*: `Given there are capital commitments of "committed_amount=1000000;currency=USD" from each investor`
*   `When I create a new capital call {string}`
    *   *Inputs*: `percentage_called`, `call_basis` ("Percentage of Commitment", "Investable Capital Percentage", "Upload").

### **Imports & Files**
*   `Given Given import file {string} for {string}`
    *   *Usage*: `Given Given import file "commitments.xlsx" for "CapitalCommitment"`
    *   *Note*: Files must exist in `public/sample_uploads/`.
*   `Given Given I upload an investors file for the fund` (Specialized for stakeholder imports).

### **Verification & Financials**
*   `Then I should see the {string}` (Generic UI check).
*   `And the remittance rollups should be correct`
    *   *Critical*: This performs an exhaustive check of financial sums across Fund, Commitment, and Remittance levels.
*   `Then the capital call collected amount should be {string}` (Checks both Call and Fund totals).
*   `Then the investors must receive email with subject {string}`

---

## 4. Advanced Patterns

### **Asynchronous Jobs**
To test background processing (like imports or doc generation), trigger the job synchronously in your step:
```ruby
# In step definition
ImportUploadJob.perform_now(ImportUpload.last.id)
```

### **Documents & E-Signatures**
*   `When the capital call docs are generated` (Triggers PDF generation).
*   `Then the generated doc must be attached to the capital remittances`
*   `Then the document is signed by the signatories` (Uses stubs for Digio/Docusign).

### **Financial Assertions (Cents)**
Always assert financial amounts in cents to avoid floating-point issues:
```ruby
@fund.committed_amount_cents.should == CapitalCommitment.sum(:committed_amount_cents)
```

---

## 5. Pro-Tips & Debugging

*   **Logging**: Use `puts @model.to_json` in your steps to inspect the state of objects during execution.
*   **Inspection**: Use `binding.pry` to pause execution and explore the page or database.
*   **Wait Times**: Capybara is configured with a 15s wait time. Avoid `sleep` unless absolutely necessary; prefer `expect(page).to have_content(...)` which has built-in retries.
*   **Database Cleaner**: Scenarios are wrapped in a transaction (or truncation for JS tests). State is reset after each scenario.
*   **Playwright**: The project uses Playwright for browser testing. You can see the browser by setting `BROWSER=true` in your environment.

---

## 6. Annotated "Golden Scenario"

```gherkin
@javascript
Scenario Outline: End-to-End Capital Call Flow
  # 1. Setup Entity and User
  Given Im logged in as a user "first_name=Admin" for an entity "entity_type=Investment Fund;enable_funds=true"
  
  # 2. Initialize Domain Data
  And there is a fund "name=Alpha Fund;currency=USD" for the entity
  And Given import file "stakeholders.xlsx" for "Investor"
  And Given import file "commitments.xlsx" for "CapitalCommitment"
  
  # 3. Perform Business Action
  When I create a new capital call "name=Call #1;percentage_called=10;call_basis=Percentage of Commitment"
  
  # 4. Verify Immediate Results
  Then the corresponding remittances should be created
  And I should see the "Call #1"
  
  # 5. Process Workflow
  And when the capital call is approved
  And I mark the remittances as paid
  And I mark the remittances as verified
  
  # 6. Exhaustive Financial Verification
  Then the capital call collected amount should be "<expected_amount>"
  And the remittance rollups should be correct
  
  # 7. Verify Side Effects (Emails/Docs)
  And the investors must receive email with subject "Capital Call Notice"

  Examples:
    | expected_amount |
    | 1000000         |
```

---

## 7. Directory Reference
- `features/[domain]/*.feature`: Feature files.
- `features/step_definitions/*.rb`: Ruby step implementations.
- `features/support/env.rb`: Configuration and `IRMUtils` (where `key_values` lives).
- `public/sample_uploads/`: Source files for import tests.
