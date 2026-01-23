# IRM Agent Guidelines

This document provides essential information for AI agents working on the IRM (Investor Relationship Management) codebase.

## 1. Commands

### Build & Setup
- **Install Dependencies:** `bundle install && npm install`
- **Database Setup:** `bin/rails db:create db:migrate`
- **Development Server:** `bin/dev` (or `rails s -p 3001`)

### Linting & Formatting
- **RuboCop (Ruby):** `bundle exec rubocop`
- **Auto-correct:** `bundle exec rubocop -a`
- **Brakeman (Security):** `bundle exec brakeman`

### Testing
- **Run all RSpec tests:** `bundle exec rspec`
- **Run a single test file:** `bundle exec rspec spec/requests/investors_spec.rb`
- **Run a specific test case:** `bundle exec rspec spec/requests/investors_spec.rb:10`
- **Run Cucumber features:** `bundle exec cucumber`
- **Run Playwright tests:** `npx playwright test`

---

## 2. Code Style Guidelines

### Architecture: Modular Rails (Packs) & Business Logic
This project uses `packs-rails` for modularization and several design patterns for business logic. It follows a Domain-Driven Design (DDD) approach.
- **Packs:** Source code is located in `app/packs/[domain]/[sub_domain]/`.
  - **Controllers:** `app/packs/[domain]/[sub_domain]/controllers/`
  - **Models:** `app/packs/[domain]/[sub_domain]/models/`
  - **Views:** `app/packs/[domain]/[sub_domain]/views/`
  - **Policies:** `app/packs/[domain]/[sub_domain]/policies/` (using Pundit gem)
  - **Services:** `app/packs/[domain]/[sub_domain]/services/` (often using Trailblazer or simple service objects)
- **Core Infrastructure:** Essential models and logic reside in `app/packs/core`.
- **View Components:** UI components are located in `app/packs/core/components/` or within specific packs using the `view_component` gem.
- **Dataframes:** `Polars` is used for high-performance data manipulation, often within `ApplicationDataframe` subclasses.

### Ruby & Rails Best Practices
- **Respect the Layout:** Never place domain-specific controllers/models in standard `app/controllers/` or `app/models/` if a domain pack exists.
- **Authorization:** Use Pundit policies. Every controller action should call `authorize`. Ensure multi-tenancy by filtering scopes with `entity_id`.
- **Strong Parameters:** Always whitelist attributes using `params.require(:model).permit(...)`.
- **Search & Pagination:** Use **Ransack** for searching/sorting and **Pagy** for pagination.
- **Models:**
  - Use `has_rich_text` for Trix-enabled fields.
  - Implement `ransackable_attributes` and `ransackable_associations`.
  - Use `delegate` for cleaner access to associated attributes.
- **Service Objects:** Move complex business logic out of models/controllers into services.

### Frontend & Assets (Stimulus & Hotwire)
- **Stimulus JS:** Controllers are located in `app/javascript/controllers/`. Use for DOM manipulation and event handling.
- **Hotwire/Turbo:** Leverages Turbo Streams and Frames for reactivity. Use `@rails/request.js` for AJAX that returns Turbo Streams.
- **jQuery:** The project uses jQuery; it may be used within Stimulus controllers for specific interactions.
- **Assets:** Uses `importmap-rails` for most JS and `esbuild` for complex bundling. CSS uses Tailwind and custom SCSS.

### Database & Persistence
- **ActiveRecord:** Primary ORM. Use **Enumerize** for enums, **Audited** for tracking, and **Paranoia** for soft deletes.
- **Chewy:** Elasticsearch integration. Update indexes with `update_index('<index>') { self if index_record? }`.
- **ActiveStorage:** Used for file handling alongside **Shrine**.

### Testing & Quality
- **Cucumber:** Integration tests in `features/`. Scenarios in `.feature` files, steps in `step_definitions/`.
  - Reuse existing steps; use `FactoryBot` for setup; use `Capybara` for automation.
  - Refer to `features/features.md` for more info.
- **RSpec:** Primary framework for models, services, and requests.
- **Playwright:** Used for end-to-end browser testing.
- **Linting:** RuboCop for Ruby, Brakeman for security.

### Commonly Used Gems
- **Draper:** Decorators/presenters.
- **Noticed:** Notifications.
- **Money-rails:** Currency handling in cents.
- **Sidekiq:** Background processing (jobs in `<pack>/jobs/`).

---

## 3. Cursor & Copilot Rules
(No specific `.cursorrules` or `.github/copilot-instructions.md` found in root. Follow the guidelines above.)

---

## 4. Workflows for Agents

### 1. Research & Exploration
- Use `grep` or `glob` to find the relevant pack and files.
- This codebase is large and modular; always check `app/packs/` first.
- Search for existing `Trailblazer::Operation` if you're adding business logic.

### 2. Implementation Patterns
- **Adding a new feature:** Create a new pack if it's a large, isolated feature, or add to an existing one.
- **Modifying models:** Check for existing Concerns in `models/concerns`.
- **UI Changes:** Check `app/components` for existing ViewComponents before creating new ones.
- **Background Tasks:** Use Sidekiq workers (located in `jobs/` directories within packs).

### 3. Verification
- **Test First:** Try to find or create a spec for your changes.
- **Run Tests:** `bundle exec rspec <file>` is your friend.
- **Linting:** Always run `bundle exec rubocop <modified_files>` to ensure style consistency.
- **Security:** Run `bundle exec brakeman` if you make changes to controllers or data handling.

### 4. Search Indexing
- If you modify a model that is indexed (check for `update_index`), ensure you trigger an index update or verify it happens automatically.
- Use `Chewy.strategy(:atomic) { ... }` for bulk updates if necessary.

