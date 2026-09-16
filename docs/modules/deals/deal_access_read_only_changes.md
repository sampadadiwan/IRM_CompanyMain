# Deal Access: Read-Only Permission Enforcement

## Overview

This document describes recent changes to enforce read-only access for deal grid activity actions. Users with read-only deal access can now view deal activities but cannot modify their status from the deal investor grid view.

## Changes Made

### 1. Frontend Grid Controller
**File:** [app/javascript/controllers/deals_list_ag_grid_controller.js](../../../app/javascript/controllers/deals_list_ag_grid_controller.js)

#### Implementation Details:
- `canUpdateRow(data)`: Checks if `data.can_update` is true before allowing any cell edits
- `showAccessDenied()`: Displays a dismissible alert when a read-only user attempts an update
- Activity badge click handler: Hides status action buttons (`data-status="complete"`, etc.) for read-only rows

#### Key Methods:
- **onCellValueChanged()**: Validates update permission before PATCH; reverts immediately if denied
- **updateActivity()**: Sends PATCH only after `canUpdateRow()` passes
- **setupActivityMenu()**: Renders floating menu with status options hidden for `canUpdate=false`

### 2. Backend Serialization
**File:** [app/packs/startups/deals/views/deal_investors/_deal_investor.json.jbuilder](../../../app/packs/startups/deals/views/deal_investors/_deal_investor.json.jbuilder)

```ruby
json.can_update policy(deal_investor).update?
```

- Serializes update permission at JSON render time
- Uses Pundit policy `DealInvestorPolicy#update?` to compute permissions
- Respects all existing access control rules (employees, RMs, investors, admins)

### 3. Policy Logic
**File:** [app/packs/startups/deals/policies/deal_investor_policy.rb](../../../app/packs/startups/deals/policies/deal_investor_policy.rb)

#### Update Permission Rules:
1. **Company Admins**: Always allowed
2. **Employees with AccessRight (read)**: Cannot update (read-only)
3. **Employees with AccessRight (update)**: Allowed to update
4. **RMs**: Allowed (if permissioned)
5. **Support Users**: Allowed
6. **Investors**: Cannot update via this path

#### Current Logic:
```ruby
def update?
  create? ||
    permissioned_employee?(:update) || support?
end
```

Where `permissioned_employee?(perm = nil)` checks:
- User is company admin → **allow**
- User has AccessRight with permission ≥ `:update` → **allow**
- Otherwise → **deny**

## Test Coverage

### New Scenario
**File:** [features/deal/deal_step_tasks_access.feature](../../../features/deal/deal_step_tasks_access.feature)

**Scenario: "Read-only employee cannot change deal activity status from grid view"**

This test validates:
1. ✓ Employee with read-only deal access can view the deal grid
2. ✓ Activity badge opens but status action buttons are hidden
3. ✓ Attempting to change activity triggers "Access denied" message
4. ✓ No PATCH request to `/deal_activities/{id}.json` is sent
5. ✓ Current activity remains unchanged in database

**Result:** 17 steps passed ✓

### Step Definitions
**File:** [features/step_definitions/deal_step_tasks_steps.rb](../../../features/step_definitions/deal_step_tasks_steps.rb)

- **When I try to change the activity … from the grid**: Simulates read-only user clicking activity badge and attempting status change
- **Then no deal activity patch request should be sent**: Verifies fetch spy intercepted zero PATCH calls

## How Access Control Works

### Employee Access Levels

| Role | Access Type | Permission | Can Update Deal Activity? |
|------|-------------|-----------|--------------------------|
| Company Admin | N/A | All | ✓ Yes |
| Employee | AccessRight | read | ✗ No (read-only) |
| Employee | AccessRight | update | ✓ Yes |
| Employee | AccessRight | destroy | ✓ Yes (implied) |
| No AccessRight | N/A | None | ✗ No |
| RM (with access) | N/A | All | ✓ Yes |
| Investor | N/A | Limited | ✗ No (investors view "overview") |

### Data Flow

1. **DealInvestor JSON render** → Computes `can_update` via Pundit policy
2. **Grid receives JSON** → `canUpdateRow(data)` checks `data.can_update`
3. **User clicks cell** → `onCellValueChanged()` validates again before PATCH
4. **PATCH sent** → Backend policy enforces final authorization; may return 403 if policy changes
5. **UI feedback** → Access denied alert shown; cell reverted to original value

## Security Considerations

- **Dual validation**: Frontend validation + backend policy enforcement
- **No PATCH for read-only**: Network traffic minimized for denied updates
- **User feedback**: Clear messaging when access is denied
- **Audit trail**: Backend still logs all authorization checks

## Configuration

### Creating Read-Only AccessRight

```ruby
AccessRight.create!(
  entity_id: company.id,
  owner: deal,
  owner_type: "Deal",
  user_id: employee.id,
  access_to_investor_id: investor.id,
  permissions: Set[:read]  # Read-only; exclude :update
)
```

### Granting Update Permission

```ruby
access_right = AccessRight.find(...)
access_right.permissions.set(:update)
access_right.save!
```

## Related Policies

- [DealPolicy](../../../app/packs/startups/deals/policies/deal_policy.rb): Controls deal show/create/update
- [DealActivityPolicy](../../../app/packs/startups/deals/policies/deal_activity_policy.rb): Controls activity show/update/perform_action
- [AccessRightPolicy](../../../app/packs/core/access_rights/policies/access_right_policy.rb): Controls AccessRight CRUD

## Backward Compatibility

- ✓ Existing admin behavior unchanged
- ✓ Existing employee with update permissions unchanged
- ✓ API clients sending PATCH get proper 403 if denied
- ✓ Frontend gracefully handles read-only state

## Future Enhancements

1. **Bulk actions**: Validate `can_update` for bulk status/activity changes
2. **Notifications**: Alert user when access is revoked during session
3. **Audit logging**: Track all denied update attempts
4. **Permission management UI**: Simplified workflow to grant/revoke employee access levels

## Running the Test

```bash
cd /home/anios/IRM
bundle exec cucumber features/deal/deal_step_tasks_access.feature
```

Expected output:
```
1 scenario (1 passed)
17 steps (17 passed)
```

## References

- [Access Rights Review](../../security/access_rights_review.md)
- [Deals Module Guide](deals_module_guide.md)
- Pundit authorization gem: https://github.com/varvet/pundit
