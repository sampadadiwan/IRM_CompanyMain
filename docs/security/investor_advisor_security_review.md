# InvestorAdvisor Security Review

**Date:** 2026-04-25
**Scope:** `app/packs/core/investors/` — InvestorAdvisor model, controller, policy, import service; `app/packs/core/base/controllers/concerns/with_authentication.rb`
**Focus:** Privilege escalation, unauthorized access, IDOR

---

## Summary

Nine vulnerabilities were identified and fixed across the InvestorAdvisor feature. Two were Critical (arbitrary role escalation, IDOR on advisor creation), three High (missing authorization on revert path, feature flag bypass, mass-assignable sensitive fields), three Medium (state mutation on GET, nil crash + enumeration oracle, non-atomic role assignment), and one Low (permission synchronization).

| # | Severity | Title | Status |
|---|----------|-------|--------|
| 1 | Critical | `create_for_investor?` / `new_for_investor?` — tautological policy, IDOR | Fixed |
| 2 | Critical | `allowed_roles` unvalidated — arbitrary role escalation on switch | Fixed |
| 3 | High | `switch` revert path — no authorization check | Fixed |
| 4 | High | `create?` / `update?` / `destroy?` — feature flag not enforced | Fixed |
| 5 | High | `user_id`, `permissions`, `extended_permissions` mass-assignable | Fixed |
| 6 | Medium | `switch_advisor` before_action — persistent state mutation on GET | Fixed |
| 7 | Medium | `new_for_investor` — nil crash on missing fund + enumeration oracle | Fixed |
| 8 | Medium | Role assignment in `switch` / `revert` — not atomic | Fixed |
| 9 | Low | Permission synchronization — inconsistent inheritance | Fixed |

---

## Finding 1 — Critical: `create_for_investor?` Tautological Policy (IDOR)

### The Vulnerability

The Pundit policy guarding "add an advisor to a specific investor's fund" checked only that the new InvestorAdvisor record's `entity_id` matched the investor's `investor_entity_id`:

```ruby
# BEFORE — investor_advisor_policy.rb
def create_for_investor?
  investor_advisor = record[:investor_advisor]
  investor = record[:investor]
  investor_advisor&.entity_id == investor&.investor_entity_id
end
```

In the controller, the InvestorAdvisor was constructed with exactly that `entity_id` — so the check was always true regardless of who the current user was or which entity they belonged to. It said nothing about the current user's authorization.

### Attack Scenario

Blackrock Capital (entity A) uses the platform to manage Fund Alpha. Rogue Advisor Co (entity B) is a completely unrelated competitor. A user at Rogue Advisor Co logs in, opens browser dev tools, and POSTs to `POST /investor_advisors/create_for_investor` with `investor_id=123` (a Blackrock investor ID discovered through guessing or prior enumeration) and their colleague's email address.

The policy check passes — the submitted `entity_id` matches the investor's entity. Rogue Advisor Co's colleague is now registered as a legitimate advisor on Blackrock's investor. They receive an invitation email, gain an `InvestorAccess` record, log in, and can view that investor's KYC documents and capital commitment data.

### The Fix

The policy now checks that the current user's entity is the managing entity of the investor — not just that two IDs happen to match:

```ruby
# AFTER — investor_advisor_policy.rb
def create_for_investor?
  investor = record[:investor]
  belongs_to_entity?(user, investor)
end
```

`belongs_to_entity?` checks `user.entity_id == investor.entity_id` (the fund manager's entity) and handles group-company hierarchies. Additionally, the controller now forces `entity_id` server-side after authorization passes — it cannot be manipulated via params:

```ruby
# AFTER — investor_advisors_controller.rb
authorize({ investor_advisor: InvestorAdvisor.new, investor: @investor }, ...)
@investor_advisor = InvestorAdvisor.new(investor_advisor_params)
@investor_advisor.entity_id = @investor.investor_entity_id  # forced server-side
```

The Rogue Advisor Co user now receives a 403. Their `entity_id` does not match the fund manager's entity that owns investor 123.

---

## Finding 2 — Critical: `allowed_roles` Unvalidated — Arbitrary Role Escalation

### The Vulnerability

`allowed_roles` is the list of roles assigned to an advisor's user record when they call the `switch` action. It was stored as a plain serialized array with no validation. Strong params permitted it directly from user input:

```ruby
# BEFORE — investor_advisors_controller.rb
params.require(:investor_advisor).permit(
  :entity_id, :user_id, :email, allowed_roles: [], ...
)
```

Inside `switch()`, whatever was in `allowed_roles` was handed to `add_role` verbatim after wiping the user's existing roles:

```ruby
# BEFORE — investor_advisor.rb
user.roles.delete_all
allowed_roles.each { |role| user.add_role(role) }
user.add_role(:investor_advisor)
```

### Attack Scenario A — UI-based privilege escalation

At Greenfield VC (entity A), a company admin creates an InvestorAdvisor record for an external advisor. Using a standard browser and intercept proxy, the admin adds `allowed_roles[]=company_admin` to the POST payload before it is submitted. Strong params accepts it. The advisor logs in, sees the "Switch" button for Greenfield VC, and clicks it. `switch()` runs: `delete_all` wipes their roles, then `add_role("company_admin")` and `add_role(:investor_advisor)` are called. The advisor now has `company_admin` on Greenfield VC — full control of all funds, deals, investors, and other users' data.

### Attack Scenario B — Excel import

The same attack works via the bulk import spreadsheet. An importer uploads a file with the `Allowed Roles` column set to `company_admin,investor_advisor`. The import service split and stored that string without validation:

```ruby
# BEFORE — import_investor_advisor.rb
allowed_roles = user_data['Allowed Roles'].downcase.split(',').map(&:strip)
# → ["company_admin", "investor_advisor"] — stored directly
```

The advisor listed in the spreadsheet gains `company_admin` the next time they switch into that entity.

### The Fix

A constant defines the only valid roles an advisor may be granted:

```ruby
# investor_advisor.rb
ALLOWED_ADVISOR_ROLES = %w[employee investor investor_advisor].freeze
```

A model validation rejects anything outside this set before the record can be saved:

```ruby
def allowed_roles_are_valid
  invalid = Array(allowed_roles) - ALLOWED_ADVISOR_ROLES
  errors.add(:allowed_roles, "contains invalid role(s): #{invalid.join(', ')}") if invalid.any?
end
```

The import service validates before attempting to save, giving the operator a clear error:

```ruby
# import_investor_advisor.rb
invalid_roles = allowed_roles - InvestorAdvisor::ALLOWED_ADVISOR_ROLES
raise "Invalid roles in 'Allowed Roles' column: #{invalid_roles.join(', ')}" if invalid_roles.any?
```

`company_admin` can never reach the `switch` method. Both the UI form and the import path are now blocked at the validation layer.

---

## Finding 3 — High: `switch` Revert Path Has No Authorization Check

### The Vulnerability

The `switch` action has two branches: switch-to (with `params[:id]`) and revert-back (without). Only the switch-to branch called `authorize`. The revert branch was explicitly excluded from Pundit's `verify_authorized` callback:

```ruby
# BEFORE — investor_advisors_controller.rb
after_action :verify_authorized, except: %i[index switch]

def switch
  if params[:id].present?
    @investor_advisor = InvestorAdvisor.find(params[:id])
    authorize(@investor_advisor)           # ← protected
    @investor_advisor.switch(current_user)
  else
    InvestorAdvisor.revert(current_user, params[:persona])  # ← no check at all
  end
end
```

Any authenticated user — investor, employee of another entity, or a newly-created account — could POST to `/investor_advisors/switch` without an `id` parameter and trigger `revert`.

### Attack Scenario A — Account corruption via DoS

A regular investor user (role: `:investor`, `advisor_entity_id: nil`) discovers the revert endpoint. They POST to it. `revert` runs:

```ruby
user.entity_id = user.advisor_entity_id   # → nil, because investor is not an advisor
user.setup_defaults                         # → calls entity.entity_type → NoMethodError on nil
```

The user's `entity_id` is set to nil and saved before the crash. Their account is now corrupted — they can authenticate but hit errors on every subsequent page. Recovery requires a support team database intervention.

### Attack Scenario B — Silent session disruption

A legitimate advisor is switched into entity B. An attacker triggers the revert endpoint (via a shared machine, or a CSRF gadget on another tab). The advisor is silently returned to their home entity mid-session without consent. Combined with re-triggering a switch via Finding 6, this could be used to bounce an advisor between entities to introduce confusion in audit logs or exploit race conditions in access-right checks.

### The Fix

```ruby
# AFTER — investor_advisors_controller.rb
else
  raise Pundit::NotAuthorizedError unless current_user.investor_advisor?
  InvestorAdvisor.revert(current_user, params[:persona])
end
```

`investor_advisor?` returns true only when `advisor_entity_id.present? && advisor_entity_id != entity_id` — the user has an advisor home entity configured and is currently switched. Regular investors, employees, and unadvisory users receive a 403 before `revert` is called. Correctly switched advisors can still revert normally.

---

## Finding 4 — High: `create?` / `update?` / `destroy?` Bypass Feature Flag

### The Vulnerability

`index?` correctly gated the listing page behind the `enable_investor_advisors` feature flag. But the write operations did not:

```ruby
# BEFORE — investor_advisor_policy.rb
def index?
  user.enable_investor_advisors && !user.investor_advisor?   # flag checked
end

def create?
  belongs_to_entity?(user, record)   # NO flag check
end
```

Since `update?` and `destroy?` both delegated to `create?`, all write operations were accessible regardless of the feature flag.

### Attack Scenario

Sunrise Fund had the `enable_investor_advisors` feature disabled — they had not subscribed to the module and had no intention of using it. An employee at Sunrise Fund, having seen the feature on another entity's account, crafts a POST to `/investor_advisors`. They are a member of the entity, so `belongs_to_entity?` passes. An advisor record is created. The new advisor receives an invitation email and can log in and switch into Sunrise Fund's context, accessing fund and investor data — despite the feature being administratively disabled.

### The Fix

```ruby
# AFTER — investor_advisor_policy.rb
def create?
  user.enable_investor_advisors && belongs_to_entity?(user, record)
end
```

`update?` and `destroy?` delegate to `create?` and are fixed automatically. The feature flag now enforces a hard boundary at all write operations, not just the listing page.

---

## Finding 5 — High: Mass-Assignable `user_id`, `permissions`, `extended_permissions`

### The Vulnerability

Strong params permitted three fields that should only be set server-side:

```ruby
# BEFORE — investor_advisors_controller.rb
params.require(:investor_advisor).permit(
  :entity_id, :user_id, :email,
  allowed_roles: [], permissions: [], extended_permissions: []
)
```

### Attack Scenario A — `user_id` cross-entity linking

An entity admin at TechVentures submits a create advisor form with `user_id=456` — a user from a different firm who happens to have the `:investor_advisor` role from a previous engagement. While `ensure_user` resolves `user_id` from `email`, the raw `user_id` field being accepted at all allowed the admin to attempt to link arbitrary users to their entity's advisor access grants.

### Attack Scenario B — `permissions` inflation

The advisor's `permissions` bitfield controls their fund-level read/write access flags. Normally this is copied from the investor entity's own permission set. By submitting `permissions[]=all_flags`, a user could grant the new advisor broader permissions than the investor entity itself holds — for example, write access where the entity only has read-only grants. This circumvents the permission inheritance model built into the service layer.

### Attack Scenario C — `extended_permissions` injection

`extended_permissions` controls access to sensitive sub-features like `:investor_kyc_read`. An entity admin submits `extended_permissions[]=investor_kyc_read&extended_permissions[]=investor_write` to pre-load the advisor with elevated extended permissions before they switch in — bypassing the service layer that normally sets these to a fixed safe list.

### The Fix

All three fields are removed from strong params:

```ruby
# AFTER — investor_advisors_controller.rb
def investor_advisor_params
  params.require(:investor_advisor).permit(:entity_id, :email, allowed_roles: [])
end
```

- `user_id` is resolved exclusively by `ensure_user` from the trusted `email` field
- `permissions` is set by the controller from `investor.investor_entity.permissions`
- `extended_permissions` is set by the controller explicitly as `%i[investor_kyc_read investor_read]`

None of these values can be overridden from the client.

---

## Finding 6 — Medium: `switch_advisor` Mutates Persistent State on GET Requests

### The Vulnerability

```ruby
# BEFORE — with_authentication.rb
before_action :switch_advisor, if: proc { |c|
  c.current_user&.has_cached_role?(:investor_advisor) &&
  c.params[:investor_advisor_id].present?
}
```

No HTTP verb restriction. Any method — including GET — would trigger `switch_advisor` if `investor_advisor_id` appeared in the query string. Inside `switch_advisor`, the user's `entity_id` is permanently written to the database.

### Attack Scenario

An external advisor (user at Advisory Co) is browsing the app. An attacker sends them a phishing email with a link that appears to be a legitimate fund report PDF:

```
https://app.example.com/funds/42/report?investor_advisor_id=7
```

The advisor clicks it. Their GET request to `/funds/42/report` hits the `switch_advisor` before_action. Their `entity_id` is silently written to the database and they are switched into entity 7's context. The report page may error, but the switch has already persisted. The advisor is now viewing data as an advisor to entity 7, which may not be an entity they intended to advise — and the switch is invisible unless they check their displayed entity name.

This is also exploitable via open redirects, link previews that follow URLs, or any page that reflects query parameters into a redirect chain.

### The Fix

```ruby
# AFTER — with_authentication.rb
before_action :switch_advisor, if: proc { |c|
  c.request.post? &&
  c.current_user&.has_cached_role?(:investor_advisor) &&
  c.params[:investor_advisor_id].present?
}
```

State-mutating switch now only occurs on explicit POST requests, which require a Rails CSRF token. A crafted GET link with `investor_advisor_id` in the URL is ignored. The phishing link above is inert.

---

## Finding 7 — Medium: Nil Crash on Missing Fund + Enumeration Oracle

### The Vulnerability

```ruby
# BEFORE — investor_advisors_controller.rb
@fund = Fund.find_by(id: params[:fund_id])
# no nil guard
@back_to = params[:back_to] || fund_path(@fund)        # NoMethodError if @fund is nil
@bread_crumbs = { "#{@fund.name}": fund_path(@fund) }  # NoMethodError if @fund is nil
```

`Fund.find_by` returns nil for any unknown ID. Accessing `.name` on nil raises `NoMethodError`, resulting in an unhandled 500.

### Attack Scenario

An attacker sends GET requests to:

```
GET /investor_advisors/new_for_investor?investor_id=123&fund_id=X
```

varying `X` from 1 to N. When `X` is a valid fund ID in the system, the page renders (200 or 302). When `X` is invalid, `@fund.name` raises and the server returns a 500. The attacker maps which fund IDs exist by observing the differential — a classic oracle-based enumeration attack requiring no credentials beyond a valid authenticated session. In development or staging environments with verbose error pages, the 500 may additionally leak source file paths and local variable values.

### The Fix

Mirror the existing nil-guard pattern already used for `@investor`:

```ruby
# AFTER — investor_advisors_controller.rb
@fund = Fund.find_by(id: params[:fund_id])
if @fund.nil?
  authorize({ investor_advisor: nil, investor: nil }, policy_class: InvestorAdvisorPolicy)
  redirect_to funds_path, alert: "Fund not found."
  return
end
```

All fund ID values — valid or invalid — now return a consistent 302 redirect. The attacker sees identical responses and gains no differential signal.

---

## Finding 8 — Medium: Role Assignment Not Atomic in `switch` / `revert`

### The Vulnerability

```ruby
# BEFORE — investor_advisor.rb
user.roles.delete_all                        # DB write 1
allowed_roles.each { |role| user.add_role(role) }   # DB write 2..N
user.add_role(:investor_advisor)             # DB write N+1
```

Three or more separate database operations with no wrapping transaction. If the process crashes, the database connection drops, or a deadlock occurs between `delete_all` and the first `add_role`, the user is left with zero roles.

### Attack Scenario — infrastructure-induced lockout

An advisor clicks "Switch" to enter a client entity's context. A database maintenance window begins immediately after `roles.delete_all` completes. The connection drops before any `add_role` executes. The transaction is not rolled back — `delete_all` has already committed. When the DB comes back, the user's roles table has zero rows for this user.

The advisor refreshes their browser. They are still authenticated (session cookie is valid) but have no roles. Every `has_cached_role?` check returns false. Every Pundit policy returns false. They cannot access any page in the application. Recovery requires a support team member to directly execute `user.add_role(:investor_advisor)` in a Rails console.

The same failure window exists in `revert`.

### The Fix

Both role-manipulation blocks are wrapped in `ActiveRecord::Base.transaction`:

```ruby
# AFTER — investor_advisor.rb
ActiveRecord::Base.transaction do
  user.roles.delete_all
  allowed_roles.each { |role| user.add_role(role) }
  user.add_role(:investor_advisor)
end
```

If any operation inside the block raises, the entire transaction is rolled back. The user's roles remain in their pre-switch state rather than landing in an empty intermediate state. The failure surfaces as a rescued exception with a user-facing error message, rather than silently corrupting the role set.

---

## Files Changed

| File | Findings addressed |
|------|--------------------|
| `app/packs/core/investors/models/investor_advisor.rb` | #2 (role whitelist + validation), #8 (atomic transaction), Detailed inline documentation |
| `app/packs/core/investors/policies/investor_advisor_policy.rb` | #1 (for-investor policies), #4 (feature flag), Detailed inline documentation |
| `app/packs/core/investors/controllers/investor_advisors_controller.rb` | #1 (entity_id forced server-side), #3 (revert guard), #5 (strong params), #7 (fund nil-guard), Detailed inline documentation |
| `app/packs/core/base/controllers/concerns/with_authentication.rb` | #6 (POST-only verb guard), Detailed inline documentation |
| `app/packs/core/investors/services/import_investor_advisor.rb` | #2 (role whitelist in import), Detailed inline documentation |
| `features/advisor/investor_advisor.feature` | Added `SEC-1` through `SEC-17` security scenarios |
| `features/step_definitions/investor_advisor.rb` | Implemented security assertions and permission synchronization checks |

---

## Verification Results

All security scenarios (`@security` tag) pass successfully.

```bash
bundle exec cucumber features/advisor/investor_advisor.feature --tags @security
```

Key scenarios verified:
- **SEC-2**: Import rejection of invalid roles.
- **SEC-4/5**: IDOR protection on advisor creation.
- **SEC-6/7**: Feature flag enforcement.
- **SEC-10**: GET request switch prevention.
- **SEC-12**: Permission synchronization and role scoping after switch.
