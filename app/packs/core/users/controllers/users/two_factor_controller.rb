module Users
  class TwoFactorController < ApplicationController
    layout "devise"

    # The actions that check a code the user typed: the login code, and the three
    # enrollment confirmations. All four share one attempt count per challenge (H13).
    CODE_CHECK_ACTIONS = %i[create verify_enrollment verify_whatsapp_enrollment verify_sms_enrollment].freeze

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
    # H13 — every action that checks a typed code refuses up front when the challenge has
    # already used its attempts (server count, so a replayed cookie does not help) or the
    # account is locked. Declared after the guards above so it runs once they have passed.
    before_action :refuse_spent_challenge, only: CODE_CHECK_ACTIONS

    # Shown when a wrong code takes the user to TwoFactorVerifier::USER_MISS_LIMIT in an hour.
    LOCKED_MESSAGE = "Your account has been locked after too many incorrect codes. " \
                     "We have emailed you a link to unlock it.".freeze

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
      # The Verify-vs-TOTP decision is TwoFactorVerifier's, shared with the LP mobile app sign-in
      if TwoFactorVerifier.verify(@user, submitted_code, verify_code_sent: session[:otp_code_channel] == "verify")
        complete_login
      else
        # Counted server side as well as in the session — see handle_wrong_code
        handle_wrong_code(:new)
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
        # The mode is committed HERE, not at selection — see select_mode_post and commit_method!
        commit_method!("authenticator")
        sign_in(@user)
        reset_otp_session
        # Same landing as the WhatsApp and SMS enrollments — there is no backup-codes
        # screen to pass through any more. after_sign_in_path_for, like complete_login: a
        # magic link's return-to page survives a required set-up too (E15), else the dashboard.
        redirect_to after_sign_in_path_for(@user), notice: "Two-factor authentication is now enabled."
      else
        # H13-X — enrollment codes count against the challenge like login codes; a re-render
        # needs the QR code again, so it is rebuilt only when the page is shown
        handle_wrong_code(:enroll) do
          # Must match the label/issuer used by #enroll — a different one renders a different
          # QR code, so a user who mistyped their first code would be told to re-scan.
          @provisioning_uri = @user.otp_provisioning_uri("CapHive:#{@user.email}",
                                                         issuer: "CapHive")
          @qr_code = RQRCode::QRCode.new(@provisioning_uri)
        end
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
        # Mode (and, for a required user, the flag) committed once the code verified
        commit_method!("whatsapp")
        sign_in(@user)
        reset_otp_session
        redirect_to after_sign_in_path_for(@user), notice: "Two-factor authentication via WhatsApp is now enabled."
      else
        # H13-X — counted against the challenge like a login code
        handle_wrong_code(:enroll_whatsapp)
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
        # Mode (and, for a required user, the flag) committed once Twilio approved the code (E17)
        commit_method!("sms")
        sign_in(@user)
        reset_otp_session
        # A user who loses their number needs an administrator reset — the same as every
        # other mode.
        redirect_to after_sign_in_path_for(@user), notice: "Two-factor authentication via text message is now enabled."
      else
        # H13-X — counted against the challenge like a login code
        handle_wrong_code(:enroll_sms)
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

    # Commits the method the user just proved with a code — the one place the enrollment
    # actions write two_factor_mode (verify_enrollment, verify_whatsapp_enrollment,
    # verify_sms_enrollment).
    #
    # two_factor_enabled is written too, but ONLY when it is false and the role rule requires
    # two-factor (H2, E17 — a support / super user reached set-up through the rule, not their own
    # switch). For anyone else the flag is left alone: it is already true (that is how an otp
    # session exists at all), and writing it again would silently undo an administrator who
    # switched 2FA off for this user while they were mid-enrollment (design D3). Abandoning
    # set-up before this point stores nothing (E11, X1).
    #
    # @param mode [String] "authenticator", "whatsapp" or "sms"
    def commit_method!(mode)
      attrs = { two_factor_mode: mode }
      # D3 — the role rule switches the flag on only at the moment a method is confirmed
      attrs[:two_factor_enabled] = true if !@user.two_factor_enabled? && @user.two_factor_required?

      ActiveRecord::Base.connected_to(role: :writing) { @user.update!(attrs) }

      # H2 — "turned on" security email to the user, after the update! returned (never inside a
      # transaction that could roll back). Every confirmed method gets it, voluntary or required.
      UserMailer.with(entity_id: @user.entity_id, user_id: @user.id, mode:).two_factor_enabled.deliver_later
    end

    # Records that the code the user is about to receive came from Twilio Verify.
    #
    # A hint, not the source of truth — see TwoFactorVerifier.verify_code_pending? for why.
    def mark_verify_code_sent
      session[:otp_code_channel] = "verify"
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

    # What the user typed, minus whitespace (see TwoFactorVerifier.normalize)
    def submitted_code
      TwoFactorVerifier.normalize(params[:otp_code])
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

    # A wrong code on any CODE_CHECK_ACTIONS: count it, then either show `template` again with
    # the attempts left, or end the challenge. The optional block prepares what `template`
    # needs (the authenticator enrollment's QR code) and runs only when it is rendered.
    def handle_wrong_code(template)
      # The cookie copy, as before
      increment_failed_attempts
      # The server copy, keyed by this challenge's id, plus the user's hourly count (H13)
      failure = TwoFactorVerifier.record_failure(@user, challenge_id: session[:otp_challenge_id])
      # H13-1 — max(session, server): a replayed cookie resets only the session copy. Under the
      # test env's :null_store the server copy reads 0, so the session decides as it always did.
      attempts = [session[:otp_failed_attempts], failure.attempts].max

      if failure.locked
        # H13-2 — this miss reached the hourly limit; the account is locked and the unlock email
        # is on its way, so there is nothing more to try here
        reset_otp_session
        redirect_to new_session_path(User), alert: LOCKED_MESSAGE
      elsif attempts >= TwoFactorVerifier::MAX_ATTEMPTS
        # The third wrong code ends this challenge (H13-X for the enrollment actions)
        reset_otp_session
        redirect_to new_session_path(User), alert: "Too many failed attempts. Please sign in again."
      else
        # Another try on the same screen
        flash.now[:alert] = "Invalid code. #{TwoFactorVerifier::MAX_ATTEMPTS - attempts} attempt(s) remaining."
        yield if block_given?
        render template
      end
    end

    # before_action for CODE_CHECK_ACTIONS: ends the challenge without checking the code when it
    # can no longer succeed. Checked BEFORE the code, because a check after it would still let a
    # replayed cookie's one extra guess through whenever that guess was right.
    def refuse_spent_challenge
      user = User.find(session[:otp_user_id])

      # H13-2 — a locked account takes no codes, even from a cookie saved before the lock
      if user.access_locked?
        reset_otp_session
        redirect_to new_session_path(User), alert: LOCKED_MESSAGE
        return
      end

      # H13-1 — replayed cookie: server count still applies
      attempts = [session[:otp_failed_attempts].to_i,
                  TwoFactorVerifier.challenge_attempts(session[:otp_challenge_id])].max
      return if attempts < TwoFactorVerifier::MAX_ATTEMPTS

      reset_otp_session
      redirect_to new_session_path(User), alert: "Too many failed attempts. Please sign in again."
    end

    # The key list lives with the dispatcher that starts a challenge, so both ends clear
    # the same set.
    def reset_otp_session
      TwoFactorDispatch::CHALLENGE_SESSION_KEYS.each { |key| session.delete(key) }
    end
  end
end
