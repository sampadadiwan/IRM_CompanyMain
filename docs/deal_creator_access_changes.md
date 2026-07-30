# Deal Creator Access Changes

This document describes the authorization change that gives a non-admin employee full access to a deal they create, while preserving the existing admin-controlled access-rights model.

## Summary

Before this change:

- An employee with `enable_deals` could create a deal.
- That same employee could still be blocked from managing deal steps, tasks, notes, or related deal flows if they did not also have an explicit `AccessRight` on the deal.

After this change:

- When a non-admin employee creates a deal, the system automatically grants that user a user-specific `AccessRight` on the new deal.
- That access right includes full permissions:
  - `create`
  - `read`
  - `update`
  - `destroy`
- As a result, the creator can immediately manage deal steps and other deal-scoped functionality that already relies on deal-level access rights.

## Important Constraint

This change does **not** bypass the admin restriction model.

The intended rule is:

- Deal creators get full access automatically only when no explicit user-specific deal access right already exists.
- If an admin later edits or removes that access right, the admin's restriction still wins.

In practice this means:

- We create a full-permission deal `AccessRight` for the creating employee only when that user does not already have one.
- We do **not** overwrite an existing user-specific deal access right.

That preserves the current system where admins can restrict employee permissions on individual deals, regardless of who created the deal.

## Implementation Details

### 1. Deal creation now receives the acting user

File: [app/packs/startups/deals/controllers/deals_controller.rb](../app/packs/startups/deals/controllers/deals_controller.rb)

The create action now calls:

```ruby
CreateDeal.call(deal: @deal, current_user: current_user)
```

This allows the service layer to know which employee created the deal.

### 2. CreateDeal grants creator access

File: [app/packs/startups/deals/services/create_deal.rb](../app/packs/startups/deals/services/create_deal.rb)

Inside the create transaction, after the deal is saved:

- If the actor is a non-admin employee, the service creates a user-specific `AccessRight` on the deal.
- The access right is created with full CRUD permissions.
- If a user-specific access right already exists, the service leaves it untouched.

This ensures the creator can work with the deal immediately, but explicit admin-managed permissions are not overwritten.

### 3. Deal activity policy now follows deal-level permissions consistently

File: [app/packs/startups/deals/policies/deal_activity_policy.rb](../app/packs/startups/deals/policies/deal_activity_policy.rb)

`DealActivityPolicy` was updated so that activity access is resolved through the existing deal or deal-investor policy chain:

- Template / deal-level activities use `DealPolicy`
- Investor-specific activities use `DealInvestorPolicy`

This matters because creator access is stored as a deal `AccessRight`, and the activity policy now consistently respects that deal-level access.

## What This Unlocks

For a non-admin employee who creates a deal, this change allows immediate access to:

- deal step templates
- deal activity management
- deal-scoped tasks
- deal-scoped notes flows that rely on deal or deal-investor permissions
- related update flows already driven by `DealPolicy` / `DealInvestorPolicy`

## What This Does Not Change

This change does not:

- make all employees admins
- bypass explicit `AccessRight` restrictions created by admins
- grant access across other deals automatically
- change investor or RM authorization behavior

## Validation Notes

The touched Ruby files passed RuboCop.

Browser-backed Cucumber verification was partially blocked by a local Playwright driver initialization issue unrelated to this policy change:

- `Playwright::DriverUnresponsiveError`
- `uninitialized constant Playwright::ChannelOwners::Selectors`

The authorization change was therefore implemented conservatively using the existing `AccessRight` model rather than introducing a parallel creator-only bypass.

## Related Documentation

- [docs/deal_access_read_only_changes.md](./deal_access_read_only_changes.md)
