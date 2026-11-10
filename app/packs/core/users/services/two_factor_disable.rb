# Switches a user's two-factor authentication OFF, after they re-prove their password and a
# current code in the same request (OWASP 2026-11 M8, design card ⑥, decision D5).
#
# WHY THIS EXISTS
#
# Unticking "Enable Two-Factor Authentication" used to need nothing at all, so a stolen session —
# or a company admin, support, or the admin console — could remove anyone's second factor. Now the
# User model refuses that change (User#two_factor_disable_must_be_verified) except through this
# operation, for EVERY user: a company admin's or an investor's voluntary 2FA is protected exactly
# like a support user's (H9, H10, X25).
#
# WHAT IT CHECKS, IN ORDER (modelled on TwoFactorReset)
#
#   ensure_disableable         on at all; and not a role that must use it once the date is reached (X15)
#   verify_password            Devise's valid_for_authentication? — a wrong password counts toward the
#                              account lock, so the popup is not an unlimited password oracle (X11, X14)
#   ensure_code_attempts_left  3 wrong codes per 10 minutes, checked BEFORE the code (X13); skipped when
#                              no method was ever set up — password only (E30)
#   verify_code                TwoFactorVerifier.verify: the same TOTP / Twilio Verify rules as sign-in;
#                              a miss also counts toward the hourly lock (record_user_miss)
#   switch_off                 the one in-app writer the model guard lets through; audited
#   notify                     the user, and the firm's other company admins (H9, H10, E40)
#
# Authorization (self, website session, not support acting as the user) is the controller's job —
# UserPolicy#disable_two_factor?.
#
# Usage:
#   result = TwoFactorDisable.call(user:, actor: current_user, password: params[:password], code: params[:otp_code])
#   result.success? / result[:errors] / result[:attempts_left]
class TwoFactorDisable < Trailblazer::Operation
  # Wrong codes allowed per user in CODE_WINDOW — the sign-in challenge's own limit
  MAX_CODE_ATTEMPTS = TwoFactorVerifier::MAX_ATTEMPTS
  CODE_WINDOW = 10.minutes
  CACHE_PREFIX = "two_factor_disable".freeze

  step :ensure_disableable
  step :verify_password
  step :ensure_code_attempts_left
  step :verify_code
  # Single failure handler: any refusal above lands here, then ends on the failure track
  left :handle_errors, Output(:failure) => End(:failure)
  step :switch_off
  step :notify

  # The per-user count of wrong codes in the last CODE_WINDOW
  def self.code_attempts_key(user)
    "#{CACHE_PREFIX}:#{user.id}"
  end

  # Nothing to turn off, or a role that must keep it (X15). A second submit after success fails
  # here too, so it sends no second email.
  def ensure_disableable(ctx, user:, **)
    ctx[:refusal] = :not_disableable
    if !user.two_factor_enabled?
      ctx[:errors] = "Two-factor authentication is not enabled for this user."
      false
    elsif user.two_factor_required?
      # X15 — support / super once the region's date is reached; before it nothing is refused (E42)
      ctx[:errors] = "Two-factor authentication is required for your role and cannot be turned off."
      false
    else
      true
    end
  end

  # X11 / X14 — counted like a website sign-in: failed_attempts +1, locked at Devise's maximum
  def verify_password(ctx, user:, password:, **)
    ctx[:refusal] = :password
    ok = ActiveRecord::Base.connected_to(role: :writing) do
      user.valid_for_authentication? { user.valid_password?(password.to_s) }
    end
    return true if ok

    ctx[:errors] = "The password you entered is incorrect."
    false
  end

  # X13 — refused BEFORE the code is checked, so even a correct code waits out the 10 minutes
  def ensure_code_attempts_left(ctx, user:, **)
    ctx[:refusal] = :code_attempts
    # E30 — two-factor on but no method stored: nothing to type, password only
    return true if user.two_factor_mode.blank?

    used = Rails.cache.read(self.class.code_attempts_key(user)).to_i
    ctx[:attempts_left] = [MAX_CODE_ATTEMPTS - used, 0].max
    return true if used < MAX_CODE_ATTEMPTS

    ctx[:errors] = "Too many incorrect codes. Try again in 10 minutes."
    false
  end

  # H9 / H10 / E36 — the same check as the sign-in code screen (TOTP, or Twilio Verify for SMS)
  def verify_code(ctx, user:, code:, **)
    ctx[:refusal] = :code
    # E30 — no method, no code
    return true if user.two_factor_mode.blank?
    return true if TwoFactorVerifier.verify(user, code)

    # X12 — a miss: this window's count (atomic across servers) and the hourly lock count
    used = Rails.cache.increment(self.class.code_attempts_key(user), 1, expires_in: CODE_WINDOW).to_i
    locked = TwoFactorVerifier.record_user_miss(user)
    ctx[:attempts_left] = [MAX_CODE_ATTEMPTS - used, 0].max

    ctx[:errors] = if locked
                     # The hourly limit locked the account; Devise has emailed the unlock link
                     Users::TwoFactorController::LOCKED_MESSAGE
                   elsif ctx[:attempts_left].zero?
                     # X13 — the third miss ends this window
                     "Too many incorrect codes. Try again in 10 minutes."
                   else
                     # X12 / E34
                     "The code you entered is incorrect. #{ctx[:attempts_left]} attempt(s) remaining."
                   end
    false
  end

  # Logged without the password or the code (lld.md Error Mapping)
  def handle_errors(ctx, user:, **)
    Rails.logger.warn "[TwoFactorDisable] refused user_id=#{user.id} reason=#{ctx[:refusal]}"
    SecurityMetrics.event(:two_factor_failed, reason: "disable_#{ctx[:refusal]}") if %i[password code].include?(ctx[:refusal])
    false
  end

  # The switch itself: the method is forgotten by clear_two_factor_method_when_disabled, the change is
  # audited with how it was proven (H9)
  def switch_off(ctx, user:, **)
    ctx[:previous_mode] = user.two_factor_mode
    proof = ctx[:previous_mode].presence || "no method"
    ActiveRecord::Base.connected_to(role: :writing) do
      user.disable_two_factor_verified!(audit_comment: "Two-factor turned off by self (password + #{proof})")
    end
    # A fresh window for the next time two-factor is on
    Rails.cache.delete(self.class.code_attempts_key(user))
    Rails.logger.info "[TwoFactorDisable] user_id=#{user.id} previous_mode=#{proof}"
    true
  end

  # After the update! returned. The user always; each OTHER active company admin of the user's own
  # firm (one query, ids only — E40 none left means only the user is told). An investor's fund
  # managers are not told: the investor is not their user.
  def notify(ctx, user:, actor:, **)
    UserMailer.with(entity_id: user.entity_id, user_id: user.id,
                    previous_mode: ctx[:previous_mode]).two_factor_disabled.deliver_later
    TwoFactorDisable.notify_company_admins(user:, actor:, event: "disabled")
    true
  end

  # Shared with TwoFactorReset (event "reset"): one email per other active company admin of the
  # user's firm — never the user or the actor themselves.
  #
  # @param event [String] "disabled" or "reset"
  def self.notify_company_admins(user:, actor:, event:)
    User.company_admins.active.where(entity_id: user.entity_id).where.not(id: [user.id, actor.id])
        .unscope(:order).distinct.pluck(:id).each do |admin_id|
      UserMailer.with(entity_id: user.entity_id, user_id: admin_id, subject_user_id: user.id,
                      actor_id: actor.id, event:).two_factor_admin_notice.deliver_later
    end
  end
end
