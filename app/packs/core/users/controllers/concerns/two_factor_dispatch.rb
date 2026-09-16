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

    # blank?, not nil?, matching require_no_verified_method in the controller: an empty
    # string (reachable through the cross-region sync, which assigns the raw column) is
    # "no method" too, and must not fall through to the authenticator branch.
    if user.two_factor_mode.blank?
      # Enabled but no VERIFIED method — never configured, chosen but abandoned before the
      # confirming code was entered (the mode is only written by the verify_* actions), or
      # cleared by TwoFactorReset (self-service "Change 2FA Method" / admin "Reset 2FA
      # Method"). Either way: choose a mode before anything can be sent. This is why a
      # reset needs no login-flow changes, and why an abandoned enrollment is not a lockout.
      select_mode_two_factor_path
    elsif user.whatsapp_mode?
      # Same refusal as the SMS branch below. SendOtpToWhatsappJob aborts silently when
      # the flag or the number is gone (an administrator unticked whatsapp_enabled, or
      # cleared users.phone), and the screen would say "Code sent to +…" and wait for a
      # code that never left. There are no backup codes, so say so and stop here.
      unless user.whatsapp_otp_enabled?
        Rails.logger.warn "[TwoFactorDispatch] whatsapp-mode user_id=#{user.id} cannot receive a " \
                          "code (whatsapp_enabled=#{user.whatsapp_enabled?}, phone_present=#{user.phone.present?})"
        session.delete(:otp_user_id)
        return :undeliverable
      end

      # Out-of-band modes send the code up front so it is in flight while the
      # verification screen renders.
      ActiveRecord::Base.connected_to(role: :writing) do
        user.send_otp_via_whatsapp
      end
      session[:otp_whatsapp_sent_at] = Time.current.to_s
      new_two_factor_path
    elsif user.sms_mode?
      # An sms-mode user whose code cannot be delivered must NOT be shown the
      # verification screen. It would say "Code texted to …" and offer a code box for a
      # message that was never sent, and there are no backup codes, so they would
      # sit there entering nothing that could ever work.
      #
      # Two ways to arrive here, both real:
      #   * the SMS_OTP_ENABLED kill switch was thrown (e.g. toll fraud detected) while
      #     users were already enrolled in sms mode;
      #   * their number stopped being textable — an admin edited users.phone to a
      #     landline or to a number that no longer parses.
      #
      # Recovery is an administrator reset, so say that rather than pretending.
      unless user.sms_otp_enabled?
        Rails.logger.warn "[TwoFactorDispatch] sms-mode user_id=#{user.id} cannot receive a " \
                          "code (feature_enabled=#{SmsDeliverable.feature_enabled?}, " \
                          "number_usable=#{user.sms_available?})"
        session.delete(:otp_user_id)
        return :undeliverable
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        user.send_otp_via_sms(OtpDelivery::PURPOSE_LOGIN)
      end
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
