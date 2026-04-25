# Security Review: SupportClientMapping

**Date:** 2026-04-25  
**Scope:** `app/packs/core/support_client_mappings/` — model, controller, policy, views  
**Threat model focus:** Privilege escalation, unauthorized entity access, impersonation, and access-control bypass

---

## Feature Overview

`SupportClientMapping` is the mechanism through which support staff (users with the `:support` role) are granted time-boxed access to a client entity. The workflow is:

1. A **super user** creates a mapping linking a support user → a client entity, with an optional `end_date`.
2. Creation cascades: sets `enable_support` permission on the entity and marks all entity employees with `enable_support: true`.
3. The **support user** calls **switch** — their `entity_id` is changed to the client entity, and they receive `:company_admin`.
4. After the work is done, they call **revert** — their `entity_id` is restored from `json_fields` and `:company_admin` is removed.
5. A **daily job** automatically disables expired mappings (past `end_date`).

The `enable_user_login` / `user_emails` flags are intended to allow a support user to log in *as* a client user for deeper inspection.

---

## Findings Summary

| # | Severity | Title |
|---|----------|-------|
| 1 | **Critical** | Expired mapping does not force revert — support user retains access indefinitely |
| 2 | **High** | `:support` role is not stripped on switch — cross-entity read access survives the context switch |
| 3 | **High** | Role revocation bypassed by revert — roles revoked while a user is switched are silently restored |
| 4 | **Medium** | `switch?` / `revert?` policy permits super users to force-switch any support user's context |
| 5 | **Medium** | `allow_login_as` email whitelist is dead code — login delegation access control is never enforced |
| 6 | **Low** | Index scope leaks disabled/expired mapping metadata to non-super users |

---

## Finding 1 — Critical: Expired Mapping Does Not Force Revert

### Location
- `app/packs/core/support_client_mappings/models/support_client_mapping.rb:16–63`
- `app/packs/core/base/jobs/daily_morning_job.rb:30`

### Description

When the daily job detects that a mapping's `end_date` has passed, it calls `disable_expired`, which calls `disable_support` on each expired record:

```ruby
# daily_morning_job.rb
SupportClientMapping.disable_expired

# support_client_mapping.rb
def self.disable_expired
  SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today)
                      .find_each(&:disable_support)
end

def disable_support
  update_column(:enabled, false)
  # ... removes entity-level enable_support permission if no other active mappings
  entity.permissions.unset(:enable_support)
  entity.save
  entity.employees.each { |u| u.update_column(:enable_support, false) }
end
```

`disable_support` correctly revokes entity-level permissions. But it **never calls `revert`**. A support user who is currently switched (their `entity_id` is already set to the client entity, and they already hold `:company_admin`) is **not affected**. Their database row still reads:

- `users.entity_id` = client entity id
- Role: `:company_admin` on that entity (from Rolify)
- `json_fields['orig_entity_id']` = their original entity (never cleared)

After expiry the user can continue to log in, navigate the client entity as a company admin, read all data, and make changes — indefinitely.

### Exploit Scenario

1. Super user grants support user Alice access to *Acme Corp* until 2026-04-30.
2. Alice calls `switch`. Her `entity_id` is now Acme Corp; she has `:company_admin`.
3. 2026-04-30 passes. Daily job runs `disable_expired` → `disable_support`.
4. Acme Corp's `enable_support` permission is removed. Alice's mapping is marked `enabled = false`.
5. Alice logs in the next morning — her session lands in Acme Corp as company admin. Nothing stops her. She can export investor data, modify records, or invite new users.
6. Because `status` now evaluates to `'Switched'` but `enabled = false`, the `revert?` policy returns `false` — Alice **cannot** revert herself either, leaving her permanently locked in the client entity with elevated privileges.

### Fix

`disable_support` must check whether the user is currently switched and, if so, force-revert before disabling:

```ruby
def disable_support
  revert if status == 'Switched'   # restore entity_id and roles first
  update_column(:enabled, false)

  other_active = entity.support_client_mappings.where.not(id: id).where(enabled: true).exists?
  unless other_active
    entity.permissions.unset(:enable_support)
    entity.save
    entity.employees.each { |u| u.update_column(:enable_support, false) }
  end
end
```

Alternatively, wrap it in a transaction so that partial failures don't leave inconsistent state.

---

## Finding 2 — High: `:support` Role Not Stripped on Switch — Cross-Entity Read Access Survives

### Location
- `app/packs/core/support_client_mappings/models/support_client_mapping.rb:70–80` (switch method)
- `app/packs/core/base/policies/application_policy.rb:115–139` (permissioned_employee?)

### Description

The `switch` method comment says *"Grants company_admin role and removes support role"*, but the code only does half of that:

```ruby
def switch
  if enabled && entity.enable_support
    user.json_fields['orig_entity_id'] ||= user.entity_id
    user.json_fields['orig_roles'] ||= user.roles.pluck(:name)
    user.update_columns(entity_id: entity.id, json_fields: user.json_fields,
                        entity_type: entity.entity_type)
    user.add_role(:company_admin)
    # ⚠ user.remove_role(:support) is NEVER called
  end
end
```

After the switch, the user holds **both** `:company_admin` (on the client entity) and `:support` (global). The `:support` role is checked in `ApplicationPolicy#permissioned_employee?`:

```ruby
def permissioned_employee?(perm = nil, owner: nil)
  if belongs_to_entity?(user, record)
    # company_admin / access_rights checks …
  else
    support?   # ← returns true as long as user.has_cached_role?(:support)
  end
end
```

`belongs_to_entity?` compares `user.entity_id` with `record.entity_id`. After a switch, `user.entity_id` is the client entity (Acme Corp). When Alice accesses a record belonging to a *different* client (Beta LLC), `belongs_to_entity?` returns `false`, the code falls through to `support?`, and Alice's still-present `:support` role grants read access to Beta LLC's data.

The scope policies for most resources behave the same way — the `:support` flag unlocks cross-entity visibility.

### Exploit Scenario

1. Support user Alice is mapped to Acme Corp and calls `switch`. She's now Acme Corp company admin.
2. Alice's `:support` role was never removed.
3. Alice navigates to `/funds` or any other resource URL. Because most scopes check `support?`, Alice sees (and can read) funds, investors, and documents belonging to Beta LLC, Gamma Inc, and every other entity on the platform.
4. She never needed to be mapped to those entities.

This is a **horizontal privilege escalation**: the scope of data access after switching is broader than the scope of the granted mapping.

### Fix

```ruby
def switch
  if enabled && entity.enable_support
    user.json_fields['orig_entity_id'] ||= user.entity_id
    user.json_fields['orig_roles'] ||= user.roles.pluck(:name)
    user.update_columns(entity_id: entity.id, json_fields: user.json_fields,
                        entity_type: entity.entity_type)
    user.remove_role(:support)      # ← add this
    user.add_role(:company_admin)
  else
    raise 'Cannot switch a disabled mapping'
  end
end
```

`revert` already re-adds `:support` after removing `:company_admin`, so the symmetry is correct once the removal is in place.

---

## Finding 3 — High: Role Revocation Bypassed by Revert

### Location
- `app/packs/core/support_client_mappings/models/support_client_mapping.rb:87–105` (revert method)

### Description

During `revert`, all roles captured at switch-time are blindly re-applied:

```ruby
def revert
  if enabled
    orig_entity_id = user.json_fields['orig_entity_id']
    orig_entity    = Entity.find_by(id: orig_entity_id)
    orig_roles     = user.json_fields['orig_roles'] || []
    if orig_entity_id.present?
      user.update_columns(entity_id: orig_entity_id, entity_type: orig_entity.entity_type)
      user.add_role(:support)
      user.remove_role(:company_admin)
      orig_roles.each do |role|           # ⚠ blindly restores cached roles
        user.add_role(role) unless user.has_role?(role)
      end
    end
  end
end
```

`orig_roles` is populated once at switch time (using `||=`). If an administrator revokes roles from Alice *while she is switched* (e.g., in response to a security incident), those revocations are entirely undone when Alice calls `revert`.

`forbid_bad_role` blocks the `:super` role specifically, but `:support`, `:company_admin`, `:approver`, `:signatory`, and any other role can be restored by this path.

### Exploit Scenario

1. Support user Alice has roles `[:support, :approver]`. She calls `switch`; `orig_roles = ['support', 'approver']`.
2. The security team discovers Alice has been acting inappropriately and revokes her `:approver` and `:support` roles.
3. Alice calls `revert`. The `orig_roles` cache still holds `['support', 'approver']`.
4. Both roles are re-added. The administrator's revocation is silently undone.
5. Alice is back to her original access level despite the explicit security action taken against her.

### Fix

On revert, do **not** replay cached roles unconditionally. Instead, re-add only the role appropriate to a support user and allow administrators to grant any additional roles separately:

```ruby
def revert
  if enabled
    orig_entity_id = user.json_fields['orig_entity_id']
    orig_entity    = Entity.find_by(id: orig_entity_id)
    if orig_entity_id.present?
      user.update_columns(entity_id: orig_entity_id, entity_type: orig_entity.entity_type)
      user.remove_role(:company_admin)
      user.add_role(:support)
      # Clear the cache so a second revert can't replay stale data
      user.json_fields.delete('orig_entity_id')
      user.json_fields.delete('orig_roles')
      user.update_column(:json_fields, user.json_fields)
    else
      raise 'No previous entity to revert to'
    end
  else
    raise 'Cannot revert a disabled mapping'
  end
end
```

If there are roles other than `:support` that need to survive a switch/revert cycle, verify they are still current at revert time rather than reading from the cache:

```ruby
orig_roles.each do |role|
  user.add_role(role) if user.roles.exists?(name: role)  # re-validate still assigned
end
```

---

## Finding 4 — Medium: Super User Can Force-Switch Any Support User's Context

### Location
- `app/packs/core/support_client_mappings/policies/support_client_mapping_policy.rb:2–8`
- `app/packs/core/support_client_mappings/controllers/support_client_mappings_controller.rb:64–73`

### Description

The `switch?` and `revert?` policy methods allow super users to act on **any** mapping:

```ruby
def switch?
  show? && record.enabled? && record.status != 'Switched' && record.entity.enable_support
end

def show?
  super_user? || (record.user_id == user.id && record.enabled?)
  #  ↑ super_user? passes regardless of whether the super user owns the mapping
end
```

The controller's `switch` action calls `@support_client_mapping.switch`, which operates on `self.user` (the *mapping's* user — e.g., Alice), **not** `current_user` (the super user who triggered the request):

```ruby
# controller
def switch
  @support_client_mapping.switch   # modifies mapping.user, not current_user
  redirect_to ..., notice: "User is now acting as #{current_user.reload.entity.name}."
  # ↑ the notice even shows the super user's entity, not Alice's new entity — a red herring
end

# model
def switch
  user.update_columns(entity_id: entity.id, ...)   # user == Alice
  user.add_role(:company_admin)                    # grants Alice company_admin silently
end
```

A super user can therefore:
- Force Alice into any client entity (changing her `entity_id`) without Alice initiating or consenting.
- Grant Alice `:company_admin` on that entity silently.
- Combine with Finding 2: Alice's `:support` role remains, so she gets broad cross-entity read access.

### Exploit Scenario

1. Malicious super user (or a compromised super account) wants to elevate support user Alice.
2. Creates a mapping for Alice → Acme Corp, then immediately calls `PATCH /support_client_mappings/{id}/switch`.
3. Alice's `entity_id` is now Acme Corp. Alice has `:company_admin` on Acme Corp and (due to Finding 2) read access to all entities.
4. The malicious super user can revert Alice later, covering their tracks, while Alice had access the whole time.
5. Audit logs show Alice's actions under Alice's account, not the super user's.

### Fix

Restrict `switch?` and `revert?` so only the **mapped user themselves** can initiate:

```ruby
def switch?
  record.user_id == user.id && record.enabled? && record.status != 'Switched' && record.entity.enable_support
end

def revert?
  record.user_id == user.id && record.enabled? && record.status == 'Switched'
end
```

Super users still retain full CRUD management capability (`create?`, `update?`, `destroy?`) — they just cannot *impersonate* the switch on behalf of another user.

---

## Finding 5 — Medium: `allow_login_as` Email Whitelist Is Dead Code — Login Delegation Is Uncontrolled

### Location
- `app/packs/core/support_client_mappings/models/support_client_mapping.rb:115–121`
- `app/packs/core/users/controllers/users_controller.rb:95–119` (`no_password_login` action)

### Description

`SupportClientMapping` stores two fields intended to gate login delegation:

- `enable_user_login` — boolean, defaults to `false`
- `user_emails` — comma-separated email whitelist

These are enforced by:

```ruby
def allow_login_as(email)
  if user_emails.present?
    enable_user_login && user_emails.split(',').map(&:strip).include?(email)
  else
    enable_user_login
  end
end
```

`allow_login_as` is called **only** in Cucumber step definitions (test files). It is **never called** in any controller, service, or authentication callback.

The `no_password_login` action, which is the actual login-delegation path, only checks if the current user has the `:support` role:

```ruby
def no_password_login
  support_user_id = current_user&.has_cached_role?(:support) ? current_user.id : nil
  # ... signs in @user, sets session[:support_user_id]
  # ⚠ no check against allow_login_as
end
```

Any user with `:support` role can login as any other user without restriction. The `enable_user_login = false` default is silently ignored.

### Exploit Scenario

1. Super user creates a mapping for Alice → Acme Corp with `enable_user_login: false` and `user_emails: ""` — explicitly intending to **prevent** Alice from logging in as Acme Corp employees.
2. Alice logs in as herself, navigates to Bob's profile (Bob is an Acme Corp employee), obtains a signed login link (e.g., by generating a magic link via the UI).
3. Alice uses the signed link via `no_password_login`. The system checks only `current_user.has_cached_role?(:support)` → `true`. Alice is now logged in as Bob.
4. The `allow_login_as` restriction the admin configured is entirely ignored.

### Fix

1. Call `allow_login_as` in `no_password_login` before signing in the target user:

```ruby
def no_password_login
  support_user_id = current_user&.has_cached_role?(:support) ? current_user.id : nil
  # ... find @user from signed_id ...
  if support_user_id.present?
    mapping = SupportClientMapping.find_by(user_id: support_user_id,
                                           entity_id: @user.entity_id, enabled: true)
    unless mapping&.allow_login_as(current_user.email)
      redirect_to root_path, alert: "Login delegation not permitted"
      return
    end
  end
  sign_in @user
  session[:support_user_id] = support_user_id if support_user_id.present?
  # ...
end
```

2. Fix the case-insensitive comparison in `allow_login_as` (email addresses are case-insensitive):

```ruby
def allow_login_as(email)
  if user_emails.present?
    enable_user_login && user_emails.split(',').map { |e| e.strip.downcase }.include?(email.downcase)
  else
    enable_user_login
  end
end
```

---

## Finding 6 — Low: Index Scope Exposes Disabled Mapping Metadata

### Location
- `app/packs/core/support_client_mappings/policies/support_client_mapping_policy.rb:10–18`

### Description

The Pundit scope for non-super users is:

```ruby
def resolve
  if user.super?
    scope.all
  else
    scope.where(user_id: user.id)
  end
end
```

It filters by `user_id` but not by `enabled`. A non-super user's index page lists all their mappings — including disabled/expired ones. The `show?` policy correctly requires `record.enabled?` for non-super users, so they cannot navigate to the detail page. But the index listing reveals:

- That a mapping to a given entity existed (and was revoked).
- The entity name.
- The `end_date` (visible in the index partial).

### Fix

Restrict the scope to currently enabled mappings for non-super users:

```ruby
scope.where(user_id: user.id, enabled: true)
```

---

## Risk Matrix

| Finding | Exploitable by | Access required | Impact |
|---------|---------------|-----------------|--------|
| 1 — Expired mapping retention | Any switched support user | Active support account that was switched before expiry | Full company_admin in client entity indefinitely |
| 2 — :support role not stripped | Any support user after switch | Support account with a mapping | Read access to ALL entity data platform-wide |
| 3 — Role revocation bypass | Switched support user | Ongoing support access at time of revocation | Security incident response bypassed |
| 4 — Super force-switch | Malicious/compromised super | Super account | Silently elevate any support user, cover tracks via Alice's audit trail |
| 5 — allow_login_as dead code | Any :support role user | Support account | Login-as any client user regardless of admin whitelist |
| 6 — Disabled mapping in index | Any support user | Support account | Information disclosure (mapping history) |

---

## Fix Priority

1. **Finding 1** — patch `disable_support` to call `revert` if the user is currently switched. This is a one-line fix with critical impact.
2. **Finding 2** — add `user.remove_role(:support)` in `switch`. Simple, symmetric with `revert`.
3. **Finding 3** — stop blindly replaying `orig_roles` in `revert`; clear the json_fields cache after revert.
4. **Finding 5** — wire `allow_login_as` into `no_password_login` before `sign_in`.
5. **Finding 4** — tighten `switch?` / `revert?` policy to require `record.user_id == user.id`.
6. **Finding 6** — add `enabled: true` to the non-super scope.
