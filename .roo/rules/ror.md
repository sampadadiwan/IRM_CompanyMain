---
description: Ruby on Rails specific best practices and conventions.
globs: app/**/*.rb, config/**/*.rb, db/**/*.rb, lib/**/*.rb, spec/**/*.rb
alwaysApply: true
---

- **Adhere to Ruby on Rails Conventions:**
  - The current project does not use the standard rails layout, instead it uses app/packs/'domain'/'sub_domain' where all the controllers, models, views etc reside for the sub_domain
  - The project uses Pundit gem and hence has a Policy class for each model, and uses TralBlazer to generate Services which create, update or do any other business logic.
  - The project also uses cucumber tests (in the features/ folder), which uses playwright and capybara.
  - Always use FatoryBot.create to create test mocks based on the factories.rb file
  - Follow the "Convention over Configuration" principle.
  - Use RESTful routes and actions.
  - Organize code according to the Rails directory structure.

- **Validate User Inputs:**
  - Use Rails' built-in validations in models (e.g., `validates :name, presence: true`).
  - Sanitize and escape user-provided data to prevent XSS and SQL injection.

- **Use Strong Parameters:**
  - Always use `params.require(:model).permit(:attribute1, :attribute2)` in controllers to whitelist allowed attributes for mass assignment.

- **Implement Authentication and Authorization:**
  - Use gems like `Devise` for authentication.
  - Use gems like `Pundit` for authorization.

- **Define Routes Properly:**
  - Use `resources` in `config/routes.rb` for standard RESTful routes.
  - Avoid exposing unnecessary endpoints.
  - Use `only` and `except` to limit generated routes.

- **Regularly Update Rails and Dependencies:**
  - Keep Rails and all gems updated to benefit from security patches and performance improvements.
  - Use `bundle outdated` to check for outdated gems.

- **Use Background Jobs for Long-Running Tasks:**
  - Use `Active Job` with adapters like `Sidekiq` or `Resque` for tasks like sending emails, processing images, or generating reports.

- **Implement Proper Error Handling and Logging:**
  - Use Rails' default error handling mechanisms.
  - Configure logging levels appropriately for different environments.
  - Use gems like `Rollbar` or `Sentry` for error tracking.

- **Use Partials and Helpers:**
  - DRY (Don't Repeat Yourself) up views by using partials for reusable UI components.
  - Use helpers for view-specific logic.

- **Ensure Reversible Database Migrations:**
  - Write migrations that can be rolled back (e.g., use `change` method or `up`/`down` methods).
  - Document complex migrations.

- **Use Environment Variables for Configuration:**
  - Store sensitive information (API keys, database credentials) in environment variables (e.g., using `dotenv-rails`).
  - Do not hardcode sensitive data in the codebase.

- **Implement Caching Strategies:**
  - Use `Rails.cache` for fragment caching, page caching, and action caching to improve performance.
  - Consider using Redis or Memcached as a cache store.

- **Write Comprehensive Tests:**
  - Use `Cucumber` and `Capybara` for integration, and system tests under the features/ folder.
  - Reuse the steps provided under features, if possible
  - Use FactoryBot and use the factories.rb file, do not modify existing factories, but you can add.
  - Do not create mocks which are not actually written to the DB.
  - Aim for high test coverage.
  - Write tests for models, controllers, views, and helpers.

- **Use RuboCop for Code Style:**
  - Enforce consistent code style and quality using `RuboCop`.
  - Configure `.rubocop.yml` to match project standards.

- **Regularly Back Up Database:**
  - Implement a strategy for regular database backups and disaster recovery.

- **Use Version Control Systems:**
  - Use Git for managing code changes and collaborating with team members.
  - Follow a consistent branching strategy (e.g., Git Flow, GitHub Flow).

- **Document Code and APIs:**
  - Write clear and concise comments for complex logic.
  - Document APIs using tools like `Rswag` or `Swagger`.

- **Implement Localization and Internationalization:**
  - Use Rails' I18n API to support multiple languages and regions.

- **Use Asset Pipeline:**
  - Manage and optimize JavaScript, CSS, and image assets using the Rails asset pipeline.

- **Monitor Application Performance:**
  - Use tools like `New Relic`, `Scout APM`, or `Prometheus` for performance monitoring.
  - Set up alerts for critical issues.