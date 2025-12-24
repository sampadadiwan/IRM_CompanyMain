# Rails Code Review Best Practices

As a senior developer on this project, the goal of code review is to ensure **maintainability**, **security**, and **architectural consistency** while fostering a culture of continuous learning.

## 1. Architectural Alignment (IRM Conventions)

Our project deviates from standard Rails patterns in specific ways. Ensure these are followed:

- **Domain-Driven Design (Packs):**
  - Code must reside in the correct pack under `app/packs/{domain}/{sub_domain}/`.
  - Controllers, Models, Views, and Jobs should be grouped by their business domain.
  - Cross-pack dependencies should be intentional and ideally minimized.

- **Business Logic (Trailblazer Services):**
  - Avoid "Fat Models" and "Fat Controllers".
  - Complex business logic (Create, Update, Import, etc.) MUST use Trailblazer services (found in `services/` folders).
  - Look for `step` definitions and proper flow control.

- **Authorization (Pundit):**
  - Every model should have a corresponding policy in `policies/`.
  - Controllers must call `authorize record` (or use the scope).
  - Review policies for proper role-based access control (RBAC).

## 2. Rails "Best Practices" & Performance

- **N+1 Queries:**
  - Check for missing `.includes`, `.preload`, or `.eager_load` in controllers and services.
  - Use `Bullet` or similar logs to identify bottlenecks during manual testing.

- **Database Health:**
  - Migrations must be reversible (`change` or `up`/`down`).
  - Add indexes for any column used in `where`, `order`, or `group by` clauses.
  - Use `find_each` or `find_in_batches` for large dataset iterations (especially in Jobs).

- **Background Jobs:**
  - Jobs should be idempotent.
  - Avoid passing complex Ruby objects; pass IDs and find the record inside the job.
  - Handle potential race conditions.

- **Validations & Security:**
  - Use Strong Parameters in controllers.
  - Ensure models have robust validations.
  - Sanitize any raw SQL or user-provided input that might lead to injection.

## 3. Clean Design & Readability

- **DRY (Don't Repeat Yourself):**
  - Extract reusable UI into Partials or View Components.
  - Extract common logic into Concerns or shared Services.

- **Naming:**
  - Use descriptive, intention-revealing names for variables, methods, and classes.
  - Follow Ruby idioms (e.g., predicate methods ending in `?`).

- **Small Methods:**
  - Methods should ideally do one thing and be under 10-15 lines.

- **Documentation:**
  - Avoid undocumented methods or classes. Every significant class and public method should have a brief comment explaining its purpose.
  - Document complex algorithms or non-obvious logic within methods using inline comments.

## 4. Testing (Cucumber & FactoryBot)

- **Integration Tests:**
  - New features MUST have corresponding Cucumber features in `features/`.
  - Reuse existing steps where possible; avoid redundant step definitions.

- **Mocks & Data:**
  - Use `FactoryBot.create` for test data.
  - **Crucial:** Ensure mocks are actually written to the DB as per our project rules.
  - Do not modify existing factories unless absolutely necessary; add new ones or use traits.

## 5. Reviewer Mindset

- **Be Kind:** Focus on the code, not the person.
- **Explain "Why":** Don't just suggest a change; explain the benefit (performance, readability, etc.).
- **Differentiate:** Distinguish between "Critical Issues" (bugs, security) and "Nitpicks" (style, minor improvements).
- **Test Locally:** If the change is significant, pull the branch and run the specific Cucumber features.
