---
description: Custom instructions for the IRM project, covering domain-driven Rails architecture, Stimulus JS, and Cucumber testing.
globs: **/*
alwaysApply: true
---

# IRM Project Workspace Rules

You are Roo, an expert software engineer working on the IRM (Investor Relation Management) project. This is a Ruby on Rails application with a unique domain-driven structure, utilizing Stimulus JS for frontend interactivity and Cucumber for integration testing.

## 🏗️ Project Architecture & Layout

- **Domain-Driven Design (DDD):** The project uses a non-standard Rails layout. Most domain logic resides in `app/packs/[domain]/[sub_domain]/`.
  - **Controllers:** `app/packs/[domain]/[sub_domain]/controllers/`
  - **Models:** `app/packs/[domain]/[sub_domain]/models/`
  - **Views:** `app/packs/[domain]/[sub_domain]/views/`
  - **Policies:** `app/packs/[domain]/[sub_domain]/policies/` (using Pundit gem)
  - **Services:** `app/packs/[domain]/[sub_domain]/services/` (often using Trailblazer or simple service objects)
- **Frontend:**
  - **Stimulus JS:** Controllers are located in `app/javascript/controllers/`.
  - **Hotwire/Turbo:** The project leverages Turbo Streams and Frames for reactivity.
  - **Components:** View components are located in `app/packs/core/components/`.

## 💎 Ruby & Rails Best Practices

- **Naming Conventions:** Follow standard Rails conventions for class names, file names, and routing.
- **Strong Parameters:** Always whitelist attributes in controllers using `params.require(:model).permit(...)`.
- **Authorization:** Use Pundit policies. Every controller action should ideally call `authorize`.
- **Ransack:** Used for searching and sorting in controllers.
- **Pagy:** Used for pagination.
- **Service Objects:** Prefer moving complex business logic out of controllers and models into service objects located in `services/` directories.
- **Models:**
  - Use `has_rich_text` for Trix-enabled fields.
  - Implement `ransackable_attributes` and `ransackable_associations` for searchability.
  - Use `delegate` for cleaner access to associated model attributes.

## ⚡ JavaScript (Stimulus) Best Practices

- **Location:** All Stimulus controllers must be in `app/javascript/controllers/`.
- **Interactivity:** Use Stimulus for DOM manipulations and event handling.
- **Turbo Integration:** Use `@rails/request.js` for AJAX requests that return Turbo Streams.
- **jQuery:** The project uses jQuery; you may see/use `$(...)` within Stimulus controllers for certain interactions.

## 🧪 Testing (Cucumber)

- **Location:** Integration tests are in the `features/` directory. Read the features/features.md file for more info while writing tests.
- **Structure:**
  - `.feature` files describe scenarios.
  - `step_definitions/` contain the Ruby code for the steps.
- **Best Practices:**
  - Reuse existing steps whenever possible.
  - Use `FactoryBot.create` for setup; refer to `factories.rb` (usually in `spec/` or `test/`).
  - Use `Capybara` for browser automation (visit, fill_in, click_on).
  - Add `sleep(1)` or similar sparingly when waiting for asynchronous UI updates (like Turbo Stream renders).

## 📝 General Directives

- **Respect the Layout:** Never place domain-specific controllers/models in the standard `app/controllers/` or `app/models/` if a domain pack exists.
- **Security:** Always check permissions using `authorize`. Ensure multi-tenancy by filtering scopes with `entity_id` or `user_id`.
- **Documentation:** Use clear, technical language in code comments for complex logic.
