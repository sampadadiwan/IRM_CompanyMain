module Users
  class TwoFactorController < ApplicationController
    layout "devise"

    # User is in pre-2FA state — not yet signed in
    skip_before_action :authenticate_user!
    skip_before_action :set_current_entity
    skip_after_action :verify_authorized
    before_action :require_otp_session
    # Enrollment is for a user with NO verified method. Once one exists the only way to a
    # different method is TwoFactorReset (password re-proven for self-service, policy for
    # admins); letting a mid-2FA user reach these pages would let them swap the method
    # without either. See require_no_verified_method.
    # except:, not only: — a new enrollment action added later is guarded by default; the
    # four listed are the login-verification actions, which a verified user must reach.
    before_action :require_no_verified_method,
                  except: %i[new create send_sms send_whatsapp]
    skip_before_action :verify_authenticity_token, only: %i[send_whatsapp send_sms]

    # ── Login verification ──────────────────────────────────────────────────

    def new
      @user = User.find(session[:otp_user_id])
    end

    # Under Twilio Verify the code a user types is no longer necessarily the TOTP value,
    # so this has to know which system issued it.
    #
    # The ambiguous case is real: an authenticator-mode user who pressed "Text me a code"
    # is holding a Verify code, but the same field still accepts the TOTP code from their
    # app. session[:otp_code_channel] records what was last SENT, so the Verify check
    # runs only when a Verify code actually exists.
    #
    # Order matters and is deliberate. Verify first (network, costs one of the
    # verification's limited attempts, so it is gated on the session flag), then TOTP
    # (local and free). Probing Verify speculatively after a failed TOTP entry would burn
    # a user's real attempts on codes that were never Verify codes.
    #
    # There are no backup codes in any mode. A user who has lost their device needs an
    # administrator reset (TwoFactorReset) — the same route WhatsApp and SMS mode always
    # had, now applied to authenticator mode too.
    def create
      @user = User.find(session[:otp_user_id])

      # Short-circuit order is the ordering described above: Verify only when a Verify
      # code is outstanding, then the local TOTP check.
      if (verify_code_pending? && TwilioSmsVerification.approved?(user: @user, code: submitted_code)) ||
         @user.validate_and_consume_otp!(submitted_code)
        complete_login
      else
        increment_failed_attempts
        if session[:otp_failed_attempts] >= 3
          reset_otp_session
          redirect_to new_session_path(User), alert: "Too many failed attempts. Please sign in again."
        else
          flash.now[:alert] = "Invalid code. #{3 - session[:otp_failed_attempts]} attempt(s) remaining."
          render :new
        end
      end
    end

    # ── Mode selection ──────────────────────────────────────────────────────
    #
    # Choosing a mode WRITES NOTHING. two_factor_mode is set only by the verify_* action
    # for that mode, once the user has proven they can produce a code with it.
    #
    # It used to be written here, and that produced a lockout with no self-service way
    # out: a user picked Authenticator, went off to install an app, and came back after
    # the session had expired. two_factor_mode already said "authenticator", so
    # TwoFactorDispatch sent them straight to the code screen for an app entry they had
    # never created, and there is no route from that screen back to enrollment. Keeping
    # the mode nil until verification means an abandoned enrollment simply lands on this
    # screen again at the next login.

    def select_mode
      @user = User.find(session[:otp_user_id])
    end

    def select_mode_post
      @user = User.find(session[:otp_user_id])
      mode = params[:two_factor_mode]

      unless %w[authenticator whatsapp sms].include?(mode)
        flash.now[:alert] = "Please select a mode."
        render :select_mode and return
      end

      # WhatsApp mode requires the flag AND a number to send to. Same reasoning as the
      # SMS check below: this POST is unauthenticated and attacker controlled, so the
      # screen having hidden the option is not a guarantee it was not submitted.
      if mode == "whatsapp" && !@user.whatsapp_otp_enabled?
        flash.now[:alert] = "WhatsApp is not available for your account. Please choose Authenticator."
        render :select_mode and return
      end

      # Re-check server side rather than trusting that the screen only offered modes the
      # user is eligible for: this is an unauthenticated POST, so the body is attacker
      # controlled. Without this, anyone mid-2FA could set themselves to a mode they can
      # never satisfy and lock their own account out.
      if mode == "sms" && !@user.sms_otp_enabled?
        flash.now[:alert] = "Text message codes are not available for your account. Please choose another option."
        render :select_mode and return
      end

      case mode
      when "whatsapp" then redirect_to enroll_whatsapp_two_factor_path
      when "sms"      then redirect_to enroll_sms_two_factor_path
      else                 redirect_to enroll_two_factor_path
      end
    end

    # ── Authenticator enrollment ────────────────────────────────────────────

    def enroll
      @user = User.find(session[:otp_user_id])

      ActiveRecord::Base.connected_to(role: :writing) do
        @user.generate_otp_secret if @user.otp_secret.blank?
        @user.save! if @user.otp_secret_changed?
      end

      @provisioning_uri = @user.otp_provisioning_uri("CapHive:#{@user.email}",
                                                       issuer: "CapHive")
      @qr_code = RQRCode::QRCode.new(@provisioning_uri)
    end

    def verify_enrollment
      @user = User.find(session[:otp_user_id])

      if @user.validate_and_consume_otp!(submitted_code)
        ActiveRecord::Base.connected_to(role: :writing) do
          # The mode is committed HERE, not at selection — see select_mode_post. Only the
          # mode: two_factor_enabled is already true (that is how an otp session exists at
          # all), and writing it again would silently undo an administrator who switched
          # 2FA off for this user while they were mid-enrollment.
          @user.update!(two_factor_mode: "authenticator")
        end
        sign_in(@user)
        reset_otp_session
        # Same landing as the WhatsApp and SMS enrollments — there is no backup-codes
        # screen to pass through any more.
        redirect_to root_path, notice: "Two-factor authentication is now enabled."
      else
        flash.now[:alert] = "Invalid code. Please try again."
        # Must match the label/issuer used by #enroll — a different one renders a different
        # QR code, so a user who mistyped their first code would be told to re-scan.
        @provisioning_uri = @user.otp_provisioning_uri("CapHive:#{@user.email}",
                                                      issuer: "CapHive")
        @qr_code = RQRCode::QRCode.new(@provisioning_uri)
        render :enroll
      end
    end

    # ── WhatsApp enrollment ─────────────────────────────────────────────────

    def enroll_whatsapp
      @user = User.find(session[:otp_user_id])

      # Same guard shape as enroll_sms: the URL is reachable directly by any user mid-2FA,
      # and without a number the screen would show "code sent to +" and wait forever.
      unless @user.whatsapp_otp_enabled?
        redirect_to select_mode_two_factor_path,
                    alert: "WhatsApp codes are not available for your account."
        return
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        # Generate secret silently — user never sees it; WhatsApp delivers the code
        @user.ensure_otp_secret_and_send_whatsapp!
      end
      session[:otp_whatsapp_sent_at] = Time.current.to_s
    end

    def verify_whatsapp_enrollment
      @user = User.find(session[:otp_user_id])

      if @user.validate_and_consume_otp!(submitted_code)
        ActiveRecord::Base.connected_to(role: :writing) do
          @user.update!(two_factor_mode: "whatsapp")
        end
        sign_in(@user)
        reset_otp_session
        redirect_to root_path, notice: "Two-factor authentication via WhatsApp is now enabled."
      else
        flash.now[:alert] = "Invalid code. Please try again."
        render :enroll_whatsapp
      end
    end

    # ── SMS enrollment ──────────────────────────────────────────────────────

    def enroll_sms
      @user = User.find(session[:otp_user_id])

      # This is a GET that spends money, so it needs both guards a POST would get.
      # Without the first, any user mid-2FA in any mode can reach the URL directly;
      # without the second, a refresh or a back-navigation sends another text.
      unless @user.sms_otp_enabled?
        redirect_to select_mode_two_factor_path,
                    alert: "Text message codes are not available for your account."
        return
      end

      return if recently_sent_sms?

      ActiveRecord::Base.connected_to(role: :writing) do
        # Same shape as WhatsApp enrollment: the secret is generated silently because
        # the user never sees it — the text message carries the code instead of a QR.
        @user.ensure_otp_secret_and_send_sms!(OtpDelivery::PURPOSE_ENROLLMENT)
      end
      session[:otp_sms_sent_at] = Time.current.to_s
      mark_verify_code_sent
    end

    def verify_sms_enrollment
      @user = User.find(session[:otp_user_id])

      # Verify, not validate_and_consume_otp! — in sms mode the code was minted by Twilio
      # and the user's otp_secret has nothing to do with it.
      if TwilioSmsVerification.approved?(user: @user, code: submitted_code)
        ActiveRecord::Base.connected_to(role: :writing) do
          @user.update!(two_factor_mode: "sms")
        end
        sign_in(@user)
        reset_otp_session
        # A user who loses their number needs an administrator reset — the same as every
        # other mode.
        redirect_to root_path, notice: "Two-factor authentication via text message is now enabled."
      else
        flash.now[:alert] = "Invalid code. Please try again."
        render :enroll_sms
      end
    end

    # ── SMS send (login verification page, and the authenticator fallback) ───

    def send_sms
      @user = User.find(session[:otp_user_id])

      # This endpoint costs real money per call, so unlike send_whatsapp it must not
      # rely on the session cooldown alone — that value lives in the caller's own cookie
      # and resets when they clear it. The durable limits (per number, per user) are
      # enforced inside TwilioSmsDelivery, which the job below runs; this check only
      # spares the queue and gives a faster answer for the common double-click.
      unless @user.sms_otp_enabled?
        render json: { error: "Text message codes are not available for your account." },
               status: :unprocessable_entity
        return
      end

      if recently_sent_sms?
        render json: { error: "Please wait a moment before requesting another code." },
               status: :too_many_requests
        return
      end

      @user.send_otp_via_sms(OtpDelivery::PURPOSE_LOGIN)
      session[:otp_sms_sent_at] = Time.current.to_s
      mark_verify_code_sent
      # Deliberately not "Code sent!" — the send is asynchronous and the durable
      # per-number limit inside TwilioSmsDelivery may still refuse it. Claiming success
      # for a message that never goes out is worse than a hedged message.
      render json: { message: "A new code is on its way. It can take a few seconds to arrive." }
    end

    # ── WhatsApp send (login verification page) ─────────────────────────────

    def send_whatsapp
      @user = User.find(session[:otp_user_id])

      # Mirrors the send_sms guard: the button is hidden for these users, but the endpoint
      # is reachable directly. Answering here means an honest error instead of "Code sent!"
      # for a job that aborts on the missing number.
      unless @user.whatsapp_otp_enabled?
        render json: { error: "WhatsApp codes are not available for your account." },
               status: :unprocessable_entity
        return
      end

      if session[:otp_whatsapp_sent_at] && Time.current - Time.parse(session[:otp_whatsapp_sent_at]) < 30
        render json: { error: "Please wait 30 seconds before requesting another code." }, status: :too_many_requests
        return
      end

      @user.send_otp_via_whatsapp
      session[:otp_whatsapp_sent_at] = Time.current.to_s
      render json: { message: "Code sent! Check your WhatsApp messages." }
    end

    private

    # Records that the code the user is about to receive came from Twilio Verify.
    #
    # A hint, not the source of truth — see verify_code_pending? for why.
    def mark_verify_code_sent
      session[:otp_code_channel] = "verify"
    end

    # Should the typed code be checked against Twilio Verify?
    #
    # Answered from DURABLE state, not from the session alone. An earlier version relied
    # only on session[:otp_code_channel], and that produced a real failure: a correct
    # code was rejected as invalid because the flag was absent from the session while
    # session[:otp_user_id] was present. Any path that writes one key but not the other —
    # a partial reload, a session reset between the send and the check, a user who
    # reaches this form from an older tab — silently sends a Verify code to the TOTP
    # checker, which can only ever reject it.
    #
    # The three cases, in order of certainty:
    #
    #   1. sms_mode? — definitive. These users have never seen a QR code, so a TOTP value
    #      is not something they can produce. Their code is always Twilio's.
    #   2. A queued SMS delivery inside the Verify code's lifetime — durable evidence
    #      that a Verify code is genuinely outstanding. This is what covers the
    #      authenticator user who pressed "Text me a code".
    #   3. The session hint, kept as a fast path.
    #
    # Still gated: an authenticator user who never requested a text matches none of
    # these, so Verify is never probed speculatively and no verification attempt is burnt.
    def verify_code_pending?
      return true if @user.sms_mode?
      return true if session[:otp_code_channel] == "verify"

      recent_sms_delivery?
    end

    # Twilio Verify holds a verification for ~10 minutes by default. Outside that window
    # there is nothing to check, so do not spend an API call finding out.
    VERIFY_CODE_TTL = 10.minutes

    def recent_sms_delivery?
      OtpDelivery.where(user_id: @user.id,
                        channel: "sms",
                        status: OtpDelivery::STATUS_QUEUED)
                 .where(created_at: VERIFY_CODE_TTL.ago..)
                 .exists?
    end

    # True when a code was sent so recently that another would be refused downstream.
    #
    # Derived from OtpSmsRateLimiter rather than hardcoded: this used to be 30 seconds
    # while the durable limit was 1 per 60, so a resend in that gap passed here and was
    # then silently refused. Reading the limiter's own window keeps them in step.
    def recently_sent_sms?
      return false if session[:otp_sms_sent_at].blank?

      window = OtpSmsRateLimiter.min_number_window
      Time.current - Time.zone.parse(session[:otp_sms_sent_at]) < window
    end

    def require_otp_session
      # Nothing here is for a signed-in user any more (the backup-codes page was the one
      # action that ran after sign_in). Reached by the back button after enrollment, or a
      # bookmarked /two_factor/new; the actions would 404 on a nil session[:otp_user_id].
      if user_signed_in?
        redirect_to root_path
        return
      end

      unless session[:otp_user_id].present?
        redirect_to new_session_path(User), alert: "Session expired. Please sign in again."
      end
    end

    # What the user typed, minus whitespace. Codes copied out of a WhatsApp or SMS
    # message routinely arrive as "123 456" or with a trailing space, and both the TOTP
    # check and Twilio Verify compare the exact string.
    def submitted_code
      params[:otp_code].to_s.gsub(/\s+/, "")
    end

    # A user who already has a verified method belongs on the code screen, not in
    # enrollment. Reached by typing an enrollment URL mid-2FA; the honest answer is to
    # put them back where the login flow sent them.
    def require_no_verified_method
      user = User.find(session[:otp_user_id])
      return if user.two_factor_mode.blank?

      redirect_to new_two_factor_path
    end

    def complete_login
      sign_in(@user)
      reset_otp_session
      redirect_to after_sign_in_path_for(@user), notice: "Signed in successfully."
    end

    def increment_failed_attempts
      session[:otp_failed_attempts] ||= 0
      session[:otp_failed_attempts] += 1
    end

    # The key list lives with the dispatcher that starts a challenge, so both ends clear
    # the same set.
    def reset_otp_session
      TwoFactorDispatch::CHALLENGE_SESSION_KEYS.each { |key| session.delete(key) }
    end
  end
end
