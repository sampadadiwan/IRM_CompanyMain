# Signed ID Access Refactoring

This document describes the refactoring of the signed ID access mechanism in the IRM application.

## Overview

The application uses `ActiveSupport::MessageVerifier` to provide secure, signed-link access to specific records (like KPI Reports) for guest users. Previously, the logic for resolving these signed IDs was duplicated across controllers and tied specifically to the `KpiReport` model.

## Changes Made

### 1. Centralized Logic in `ApplicationController`

Moved the core logic for resolving signed IDs from individual controllers into [`app/packs/core/base/controllers/application_controller.rb`](app/packs/core/base/controllers/application_controller.rb).

- **Generic Implementation:** The new `find_by_signed_id_for_user` method uses reflection to set instance variables dynamically based on the record type.
- **Improved Readability:** Simplified flow using guard clauses.
- **Policy Support:** Maintains the `signed_id_access?` singleton method on the resolved user, allowing Pundit policies to authorize guest access.

### 2. Refactored `KpiReportsController`

Cleaned up [`app/packs/startups/kpis/controllers/kpi_reports_controller.rb`](app/packs/startups/kpis/controllers/kpi_reports_controller.rb) by replacing manual signed ID resolution with a call to the base controller method.

### 3. Documentation Improvements

Added comprehensive YARD-style documentation to:
- [`ApplicationController#find_by_signed_id_for_user`](app/packs/core/base/controllers/application_controller.rb)
- [`ApplicationRecord.find_by_signed_id_for_user`](app/packs/core/base/models/application_record.rb)

## Benefits

- **Maintainability:** Logic is now in one place. Any changes to how signed links work only need to be updated once.
- **Reusability:** Other domains (e.g., Investment Opportunities, Documents) can now easily implement signed link access by calling `find_by_signed_id_for_user`.
- **Readability:** Controller code is cleaner and more focused on domain-specific logic.
- **Policy Integration:** Authorization is handled centrally in `ApplicationPolicy`, allowing consistent permission checks across all models.

## Policy Integration

The refactoring includes a new helper method in [`app/packs/core/base/policies/application_policy.rb`](app/packs/core/base/policies/application_policy.rb):

```ruby
def signed_id_access?
  user.respond_to?(:signed_id_access?) && user.signed_id_access?
end
```

### How it works:
1.  **Controller:** When a valid `signed_id` is processed, the controller uses `define_singleton_method` to add `signed_id_access? { true }` to the `user` object.
2.  **Policy:** Any policy inheriting from `ApplicationPolicy` can call `signed_id_access?` to grant permissions.

Example in `KpiReportPolicy`:
```ruby
def show?
  return true if signed_id_access?
  # ... standard authorization logic
end
```

## Persistence of Signed ID

To ensure that guest access is maintained throughout the edit, update, and show cycle, the `signed_id` must be passed between requests.

### 1. In Forms
Add a hidden field to the resource form to include the `signed_id` in the `PATCH` or `POST` request:
```erb
<%= hidden_field_tag :signed_id, params[:signed_id] if params[:signed_id].present? %>
```

### 2. In Controller Redirects
When redirecting after a successful action, ensure the `signed_id` is passed back to the URL:
```ruby
redirect_to resource_url(@resource, signed_id: params[:signed_id])
```

### 3. In Views
Ensure action links (like "Edit") preserve the `signed_id`:
```erb
<%= link_to "Edit", edit_resource_path(@resource, signed_id: params[:signed_id]) %>
```

## Usage Example

To enable signed ID access in a new controller:

1.  Ensure the model inherits from `ApplicationRecord`.
2.  In the controller's `before_action` or setup method:
    ```ruby
    def set_resource
      find_by_signed_id_for_user(params[:signed_id])
      @resource ||= Resource.find(params[:id])
    end
    ```
3.  The method will automatically set `@resource` and `@signed_id_user` if a valid `signed_id` is provided.
