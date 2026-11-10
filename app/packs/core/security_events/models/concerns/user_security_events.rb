# frozen_string_literal: true

# The User side of the security event trail (OWASP review 2026-11 M11, design card ②, K1–K3).
#
# Two hooks catch every route, so a new call site is covered without anyone remembering to add a line (D2):
#   * rolify's after_add / after_remove (declared on `rolify` in user.rb) — every add_role / remove_role from
#     the user form, imports, investor access, support switching, rake tasks… records role.granted / revoked
#     (R1). The HABTM callback runs inside the caller's transaction; SecurityEvents.record waits for it to
#     commit, so a rolled-back grant records nothing (E24). A role that was not held is not removed, so
#     rolify fires nothing and nothing is recorded (E25).
#   * one after_update_commit, record_security_changes, for the watched columns — Devise lockable, the
#     profile, a password reset, the admin console and the cross-region sync all pass through it (T2–T4,
#     A1, A3–A5, R2).
# Flags are recorded here, not added to `audit_fields` (D3): one place to look, with the firm, IP and door.
#
# Recording never raises (SecurityEvents.record rescues everything), so none of this can fail a save.
module UserSecurityEvents
  extend ActiveSupport::Concern

  included do
    after_update_commit :record_security_changes
    # E23 — roles given while the user is being created (setup_defaults, an import) have no account id until the
    # insert; they are recorded once the creation commits
    after_create_commit :record_pending_security_roles
  end

  # rolify after_add (R1, H16, E23, E26)
  def security_role_added(role)
    record_security_role("role.granted", role)
  end

  # rolify after_remove (R1, H17)
  def security_role_removed(role)
    record_security_role("role.revoked", role)
  end

  # One event per watched column that changed in the save that just committed
  def record_security_changes
    # A1 / H14 — any route that sets a new password (profile, reset link, admin console)
    SecurityEvents.record("password.changed", user: self) if saved_change_to_encrypted_password?
    # A3 / H15 — last two digits only; the full numbers stay in audits
    record_security_phone_change if saved_change_to_phone?
    # A4 / E16 / E17 / E18 — Devise lockable sets / clears locked_at
    record_security_lock_change if saved_change_to_locked_at?
    # A5 / E21 — admin console, user sync
    record_security_flag("active", "account.reactivated", "account.deactivated") if saved_change_to_active?
    # R2 / H18 — the user's "Enable support" switch
    record_security_flag("enable_support", "support_access.enabled", "support_access.disabled") if saved_change_to_enable_support?
    # T2 / E19 — switched on or off by any route
    record_security_flag("two_factor_enabled", "two_factor.enabled", "two_factor.disabled") if saved_change_to_two_factor_enabled?
    # T3 / T4 / H12 / H13 — a method confirmed, or reset by the user or an admin
    record_security_method_change if saved_change_to_two_factor_mode?
  end

  # E23 — the roles held back by record_security_role while the user was unsaved
  def record_pending_security_roles
    pending = @pending_security_roles || []
    @pending_security_roles = nil
    pending.each { |kind, role| record_security_role(kind, role) }
  end

  private

  def record_security_role(kind, role)
    # A role added to an unsaved user has no account id yet: kept until the creation commits
    if new_record?
      (@pending_security_roles ||= []) << [kind, role]
      return
    end

    SecurityEvents.record(kind, user: self,
                                details: { role: role.name, resource_type: role.resource_type, resource_id: role.resource_id })
  end

  def record_security_phone_change
    from, to = saved_change_to_phone
    SecurityEvents.record("phone.changed", user: self, details: { from: security_masked_phone(from), to: security_masked_phone(to) })
  end

  # "**42" — enough to recognise a number, useless to anyone reading the trail
  def security_masked_phone(number)
    digits = number.to_s.delete("^0-9")
    digits.empty? ? "none" : "**#{digits.last(2)}"
  end

  def record_security_lock_change
    _from, to = saved_change_to_locked_at
    if to.present?
      # E17 — Devise locks at maximum_attempts wrong passwords; TwoFactorVerifier locks after too many codes (E16)
      reason = failed_attempts.to_i >= Devise.maximum_attempts ? "too_many_passwords" : "too_many_codes"
      SecurityEvents.record("account.locked", user: self, details: { reason: })
    else
      # E18 — an expired lock cleared at the next sign-in, or an unlock link
      SecurityEvents.record("account.unlocked", user: self)
    end
  end

  # A boolean column: on_kind when it became true, off_kind when it became false
  def record_security_flag(column, on_kind, off_kind)
    from, to = saved_changes[column]
    SecurityEvents.record(to ? on_kind : off_kind, user: self, details: { from: from.present?, to: to.present? })
  end

  def record_security_method_change
    from, to = saved_change_to_two_factor_mode
    if to.present?
      # T3 — a method confirmed at enrolment
      SecurityEvents.record("two_factor.method_set", user: self, details: { mode: to })
    elsif two_factor_enabled?
      # T4 — cleared while two-factor stays on: the next sign-in asks for a new method (TwoFactorReset)
      SecurityEvents.record("two_factor.method_reset", user: self, details: { from: })
    end
  end
end
