class IncomingEmailsController < ApplicationController
  before_action :set_incoming_email, only: %i[show edit update destroy]
  before_action :authenticate_user!, except: [:sendgrid]
  skip_before_action :verify_authenticity_token, only: [:sendgrid]
  skip_before_action :set_current_entity, only: [:sendgrid]
  skip_after_action :verify_authorized, only: [:sendgrid]
  # H2: SendGrid has no user; it proves itself with the webhook token instead
  before_action :verify_sendgrid_token, only: [:sendgrid]

  def sendgrid
    Rails.logger.debug { "Processing incoming email, to: #{params[:to]}, from: #{params[:from]}, subject: #{params[:subject]}" }

    # Deal Update Agent — route emails whose local part matches a
    # DealIngestAddress to the deal ingest pipeline. All other emails
    # fall through to the existing IncomingEmail logic below.
    # @see DealIngestAuthenticator
    if deal_ingest_email?(params[:to])
      DealIngestAuthenticator.call(params)
      return head :ok
    end

    # Extract Message-ID from the raw headers string for idempotency on SendGrid retries
    message_id = params[:headers]&.match(/Message-ID:\s*<([^>]+)>/i)&.[](1)

    if message_id.present? && IncomingEmail.exists?(message_id: message_id)
      Rails.logger.debug { "Skipping duplicate incoming email with message_id: #{message_id}" }
      return head :ok
    end

    email = IncomingEmail.new(
      from: params[:from],
      to: params[:to].truncate(255),
      subject: params[:subject],
      body: params[:html].presence || params[:text],
      cc_emails: params[:cc],
      message_id: message_id,
      # Also stored as internet_message_id, which is the dedup key the Outlook and Gmail
      # add-ins key on. Without this, an email ingested here is invisible to the add-ins'
      # already-filed check and to idx_incoming_emails_dedup (NULL never collides), so a
      # user opening that same message in Outlook is told it is unfiled and files it again.
      internet_message_id: message_id,
      received_at: Time.current
    )

    if email.save
      email.save_attachments(params)
      head :ok
    else
      Rails.logger.debug email.errors.full_messages
      head :unprocessable_entity
    end
  end

  # GET /incoming_emails
  def index
    @q = IncomingEmail.ransack(params[:q])

    @incoming_emails = policy_scope(@q.result)
    @incoming_emails = @incoming_emails.where(owner_type: params[:owner_type], owner_id: params[:owner_id]) if params[:owner_type].present? && params[:owner_id].present?
    @pagy, @incoming_emails = pagy(@incoming_emails.order(id: :desc))
  end

  # GET /incoming_emails/1
  def show; end

  # GET /incoming_emails/new
  def new
    # M22 — the blank form is the user's own firm's (IncomingEmailPolicy#create? checks the firm)
    @incoming_email = IncomingEmail.new(entity_id: current_user.entity_id)
    authorize @incoming_email
  end

  # GET /incoming_emails/1/edit
  def edit; end

  # POST /incoming_emails
  def create
    if params[:investor_id].present?
      investor = Investor.find(params[:investor_id])
      authorize investor, :update?

      # M22 — build fully (owner and firm from the investor, never from the form), then authorize
      @incoming_email = IncomingEmail.new(incoming_email_params.except(:owner_id, :owner_type, :entity_id))
      @incoming_email.owner = investor
      @incoming_email.entity = investor.entity
      @incoming_email.filed_by_user = current_user
      @incoming_email.received_at ||= Time.current
      authorize @incoming_email

      respond_to do |format|
        if @incoming_email.save
          format.json { render json: { success: true, id: @incoming_email.id } }
        else
          format.json { render json: { success: false, errors: @incoming_email.errors.full_messages }, status: :unprocessable_content }
        end
      end
    else
      # M22 — the firm is pinned from the owner (the form's entity_id is ignored), or is the user's own
      # when there is no owner; IncomingEmailPolicy#create? then checks the owner's firm and that the
      # user may update the owner (M22-1, M22-H)
      @incoming_email = IncomingEmail.new(incoming_email_params.except(:entity_id))
      @incoming_email.entity_id = incoming_email_owner_firm_id(@incoming_email.owner) || current_user.entity_id
      authorize @incoming_email
      if @incoming_email.save
        redirect_to @incoming_email, notice: "Incoming email was successfully created."
      else
        Rails.logger.debug @incoming_email.errors.full_messages
        render :new, status: :unprocessable_entity
      end
    end
  end

  # PATCH/PUT /incoming_emails/1
  def update
    if @incoming_email.update(incoming_email_params)
      redirect_to @incoming_email, notice: "Incoming email was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /incoming_emails/1
  def destroy
    @incoming_email.destroy!
    redirect_to incoming_emails_url, notice: "Incoming email was successfully destroyed.", status: :see_other
  end

  private

  # H2 — authenticates the SendGrid Inbound Parse webhook. The Inbound Parse URL configured in the
  # SendGrid dashboard carries a secret, either as ?token=<token> or as the Basic auth password
  # (https://sendgrid:<token>@host/incoming_emails/sendgrid). It is compared in constant time with
  # credentials[:sendgrid_inbound][:tokens], a list so a token can be rotated: list the new one
  # next to the old, change the URL, then drop the old one.
  # While ENV["SENDGRID_INBOUND_ENFORCE"] is not "1" an unauthenticated post is only logged and
  # carries on, so mail keeps being filed until ops have configured the URL and watched the log;
  # once it is "1" the post is refused with 401 (SendGrid retries non-2xx, so a misconfiguration
  # delays mail rather than losing it). Same shape as GrafanaAlertsController#verify_token.
  # Worked examples H2-1, H2-2, H2-R, H2-7 — docs/security/security_review_2026_10.md#h2--sendgrid-inbound-email
  def verify_sendgrid_token
    # 1. The token as SendGrid sends it: the URL's ?token= first, else the Basic auth password
    received = params[:token].presence || sendgrid_basic_auth_password
    # 2. Authenticated if it matches any configured token - the previous one too while rotating (H2-7)
    return if received.present? && sendgrid_inbound_tokens.any? { |token| ActiveSupport::SecurityUtils.secure_compare(received.to_s, token) }

    # 3. Not authenticated. Never log the token itself - only whether one was sent.
    reason = received.present? ? "wrong token" : "no token"
    if ENV["SENDGRID_INBOUND_ENFORCE"] == "1"
      # Enforced: refused, nothing is filed (H2-1 no token, H2-2 wrong token)
      Rails.logger.warn "[SendgridInbound] unauthenticated (#{reason}) from #{request.remote_ip}: refused with 401"
      head :unauthorized
    else
      # Not yet enforced: accepted as before, logged so ops can see who still posts without it (H2-R)
      Rails.logger.warn "[SendgridInbound] unauthenticated (#{reason}) from #{request.remote_ip}: accepted, SENDGRID_INBOUND_ENFORCE is off"
    end
  end

  # The password of a Basic Authorization header, or nil when there is none
  def sendgrid_basic_auth_password
    return unless ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

    ActionController::HttpAuthentication::Basic.user_name_and_password(request).last
  end

  # The accepted webhook tokens from this environment's credentials (IN and US have their own).
  # Blank entries are dropped so an empty token can never match.
  def sendgrid_inbound_tokens
    Array(Rails.application.credentials.dig(:sendgrid_inbound, :tokens)).map(&:to_s).compact_blank
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_incoming_email
    @incoming_email = IncomingEmail.find(params[:id])
    authorize @incoming_email
  end

  # M22 — the firm an owner belongs to: an Entity owner (investor presentations) is the firm itself
  def incoming_email_owner_firm_id(owner)
    return nil if owner.nil?

    owner.is_a?(Entity) ? owner.id : owner.entity_id
  end

  # Only allow a list of trusted parameters through.
  def incoming_email_params
    params.require(:incoming_email).permit(:from, :to, :subject, :body, :owner_id, :owner_type, :entity_id, :cc_emails, :message_id, :internet_message_id, :received_at)
  end

  # Whether the inbound email is addressed to a deal ingest address.
  # Extracts the local part (16-hex token) from the To field and checks
  # for an active DealIngestAddress record. This allows the deal update
  # pipeline to share the same email domain as regular incoming emails,
  # routing by address rather than by domain.
  #
  # @param to_field [String] the To field from SendGrid (may include display name)
  # @return [Boolean]
  def deal_ingest_email?(to_field)
    return false if to_field.blank?

    email = to_field.match(/<([^>]+)>/)&.[](1) || to_field.strip
    local_part = email.split("@").first&.downcase
    return false if local_part.blank?

    DealIngestAddress.for_lookup(local_part).exists?
  end
end
