module Users
  class TwoFactorController < ApplicationController
    layout "devise"

    # User is in pre-2FA state — not yet signed in
    skip_before_action :authenticate_user!
    skip_before_action :set_current_entity
    skip_after_action :verify_authorized
    before_action :require_otp_session
    skip_before_action :verify_authenticity_token, only: [:send_whatsapp]

    def new
      @user = User.find(session[:otp_user_id])
    end

    def create
      @user = User.find(session[:otp_user_id])

      if @user.validate_and_consume_otp!(params[:otp_code])
        complete_login
      elsif @user.otp_backup_codes.present? && consume_backup_code(params[:otp_code])
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

      if @user.validate_and_consume_otp!(params[:otp_code])
        ActiveRecord::Base.connected_to(role: :writing) do
          @user.update!(two_factor_enabled: true)
          session[:otp_backup_codes] = @user.generate_backup_codes!
        end
        sign_in(@user)
        reset_otp_session
        redirect_to backup_codes_two_factor_path, notice: "Two-factor authentication is now enabled."
      else
        flash.now[:alert] = "Invalid code. Please try again."
        @provisioning_uri = @user.otp_provisioning_uri("IRM:#{@user.email}",
                                                         issuer: "IRM")
        @qr_code = RQRCode::QRCode.new(@provisioning_uri)
        render :enroll
      end
    end

    def send_whatsapp
      @user = User.find(session[:otp_user_id])

      if session[:otp_whatsapp_sent_at] && Time.current - Time.parse(session[:otp_whatsapp_sent_at]) < 30
        render json: { error: "Please wait 30 seconds before requesting another code." }, status: :too_many_requests
        return
      end

      @user.send_otp_via_whatsapp
      session[:otp_whatsapp_sent_at] = Time.current.to_s
      render json: { message: "Code sent! Check your WhatsApp messages." }
    end

    def backup_codes
      @backup_codes = session[:otp_backup_codes] || []
      # Clear from session after display
      session.delete(:otp_backup_codes)
    end

    private

    def require_otp_session
      return if user_signed_in?
      unless session[:otp_user_id].present?
        redirect_to new_session_path(User), alert: "Session expired. Please sign in again."
      end
    end

    def complete_login
      sign_in(@user)
      reset_otp_session
      redirect_to after_sign_in_path_for(@user), notice: "Signed in successfully."
    end

    def consume_backup_code(code)
      @user.consume_backup_code!(code)
    end

    def increment_failed_attempts
      session[:otp_failed_attempts] ||= 0
      session[:otp_failed_attempts] += 1
    end

    def reset_otp_session
      session.delete(:otp_user_id)
      session.delete(:otp_failed_attempts)
      session.delete(:otp_whatsapp_sent_at)
    end
  end
end
