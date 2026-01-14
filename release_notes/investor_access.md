# PR Description: investor_access

## 1. Overview
Implemented granular employee-level access control for investors, allowing specific permissions (Read, Create, Update, Destroy) to be assigned to employees and advisors.

## 2. Motivation
Previously, employee access to investors was less granular. There was a need to allow company admins to restrict which investors an employee can see and what actions they can perform (e.g., viewing vs. editing) through explicit permission assignments.

## 3. What Changed
- **Access Control:**
    - Updated `InvestorPolicy` ([investor_policy.rb](app/packs/core/investors/policies/investor_policy.rb)) to enforce granular permissions.
    - Added `for_employee` scope to `Investor` model ([investor.rb](app/packs/core/investors/models/investor.rb)) to filter investors based on assigned access rights.
- **UI/UX:**
    - Modified Access Rights form ([_investor_form.html.erb](app/packs/core/access_rights/views/access_rights/_investor_form.html.erb)) to include a new permissions checklist for Read, Create, Update, and Destroy.
    - Updated Investor details views ([_portfolio_company_details.html.erb](app/packs/core/investors/views/investors/_portfolio_company_details.html.erb) and [_stakeholder_details.html.erb](app/packs/core/investors/views/investors/_stakeholder_details.html.erb)) to restrict access to the "Employee Access" tab to Company Admins only.
- **User Management:**
    - Updated User form ([_form.html.erb](app/packs/core/users/views/users/_form.html.erb)) with hidden fields for extended permissions to ensure arrays are properly cleared when no checkboxes are selected.
- **Configuration:**
    - Refactored `filter_parameter_logging.rb` ([filter_parameter_logging.rb](config/initializers/filter_parameter_logging.rb)) to use modern Ruby `%i[]` symbol array syntax.

## 4. Refactoring / Behavior Changes
- **Policy Logic:** `InvestorPolicy` now checks for both `extended_permissions` (global flags like `:investor_read`) and granular `permissions` (mapped from `investor_read`, `investor_create`, etc.).
- **Access Rights:** Access rights for employees/advisors now include specific permission bits rather than just a binary "has access" relationship.

## 5. Testing
- Manual testing of the Access Rights form to ensure permissions are correctly saved.
- Verification that employees without `:investor_read` can only see investors they are explicitly granted access to.
- Verification that Company Admins retain full visibility and management capabilities.

## 6. Impact
- **Security:** Improved security by following the principle of least privilege for employee access to sensitive investor data.
- **UI:** New checkboxes in the access rights modal.

## 7. Review Focus
- Review the `specific_permissions?` helper in `InvestorPolicy` to ensure the mapping between `investor_*` and generic CRUD permissions is correct.
- Ensure the `for_employee` scope in `Investor` correctly joins with `investor_access_rights` without performance regressions on large datasets.
