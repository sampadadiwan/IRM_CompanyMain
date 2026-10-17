# Decides where a user goes after their password (or magic link) has been accepted but
# before they are actually signed in.
#
# WHY THIS IS A CONCERN AND NOT INLINE
#
# This branch existed in two places — Users::SessionsController#create for password
# login and UsersController#no_password_login for the magic-link path — and the copies
# had already drifted: one wrapped the WhatsApp send in connected_to(role: :writing) and
# the other did not.
#
# The failure mode of that drift is nasty and quiet: a mode wired into only one copy
# produces a user who can log in one way and not the other, and nothing fails loudly.
# With a third mode (SMS) it was going to happen again, so the branch lives here once.
#
# See docs/modules/two_factor_auth/twilio_sms_otp_design.md section 5.
module TwoFactorDispatch
  extend ActiveSupport::Concern

  # Every session key a two-factor challenge writes. Owned here so the dispatcher (which
  # starts a challenge) and Users::TwoFactorController#reset_otp_session (which ends one)
  # clear the same list — a key cleared in one place but not the other is exactly how a
  # stale "verify" channel hint from an abandoned SMS challenge ended up steering a later
  # authenticator login into a Twilio Verify probe.
  CHALLENGE_SESSION_KEYS = %i[otp_user_id otp_failed_attempts otp_whatsapp_sent_at
                              otp_sms_sent_at otp_code_channel].freeze

  private

  # Sets up the pending-2FA session and triggers any out-of-band code send.
  #
  # Callers remain responsible for signing the user out and performing the redirect,
  # because the two entry points differ there and this concern should not guess.
  #
  # @param user [User]
  # @return [String] path to redirect to
  # @return [Symbol] :undeliverable when the user is in an out-of-band mode (WhatsApp or
  #   SMS) but no code can be sent — callers must refuse the login rather than show a
  #   code box
  # @return [nil] when 2FA does not apply
  def two_factor_challenge_path_for(user)
    return nil unless user.two_factor_enabled?

    # A fresh password login is a fresh challenge: no attempts used, no code in flight, no
    # channel hint. Leaving any of these from an earlier, abandoned challenge misroutes
    # this one (a stale attempt count reads "Too many failed attempts" after one miss; a
    # stale "verify" hint probes Twilio with a TOTP code).
    CHALLENGE_SESSION_KEYS.each { |key| session.delete(key) }
    # Set before any sign_out, matching the ordering both call sites already relied on.
    session[:otp_user_id] = user.id

    # Which modes send a code, and when a mode is undeliverable, live in TwoFactorVerifier so
    # the LP mobile app's sign-in applies exactly the same rules. This concern keeps only the
    # session bookkeeping and the redirect for each outcome.
    case TwoFactorVerifier.start(user)
    when :choose_method
      # Enabled but no VERIFIED method — never configured, chosen but abandoned before the
      # confirming code was entered (the mode is only written by the verify_* actions), or
      # cleared by TwoFactorReset (self-service "Change 2FA Method" / admin "Reset 2FA
      # Method"). Either way: choose a mode before anything can be sent. This is why a
      # reset needs no login-flow changes, and why an abandoned enrollment is not a lockout.
      select_mode_two_factor_path
    when :undeliverable
      # A WhatsApp- or SMS-mode user whose code cannot be delivered must NOT be shown the
      # verification screen — there are no backup codes, so they would sit entering nothing
      # that could ever work. Recovery is an administrator reset.
      session.delete(:otp_user_id)
      :undeliverable
    when :whatsapp_sent
      session[:otp_whatsapp_sent_at] = Time.current.to_s
      new_two_factor_path
    when :sms_sent
      # Seeds the resend cooldown so a user cannot immediately trigger a second paid
      # send by reloading the verification screen.
      session[:otp_sms_sent_at] = Time.current.to_s
      # Tells Users::TwoFactorController#create to check this code against Twilio Verify
      # rather than the TOTP secret. Without it an sms-mode user's correct code is
      # checked against a secret they have never seen and always rejected.
      session[:otp_code_channel] = "verify"
      new_two_factor_path
    else
      # Authenticator mode — nothing to send, the user reads the code from their app.
      new_two_factor_path
    end
  end
end
