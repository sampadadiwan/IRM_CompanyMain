# frozen_string_literal: true

# Authenticates inbound emails for the Deal Update Agent pipeline.
#
# This is the security boundary. Every failed check results in a silent
# drop — no reply, no error, no indication the address exists.
#
# Authentication checks (in order):
#   1. Address lookup — does this local-part match a DealIngestAddress? → deal
#   2. Sender lookup — does the From email match a User in the entity? → user
#   3. Access check — does that user have access to the deal?
#   4. SPF/DKIM/DMARC — do the email auth headers pass?
#   5. Dedupe — has this Message-ID already been processed?
#
# @see IncomingEmailsController#sendgrid for the webhook entry point
# @see ProcessDealIngestJob for the async processing that follows

class DealIngestAuthenticator
  # Result of the authentication attempt.
  #
  # @attr success [Boolean] whether all checks passed
  # @attr reason [String, nil] why it failed (for logging only, never exposed)
  Result = Struct.new(:success, :reason, keyword_init: true)

  # Authenticate an inbound email and create an AgentIngestedEmail if valid.
  #
  # @param params [ActionController::Parameters] the raw SendGrid webhook params
  # @return [Result] success/failure with reason
  def self.call(params)
    new(params).authenticate
  end

  def initialize(params)
    @params = params
    @to = params[:to]
    @from = params[:from]
    @headers = params[:headers]
    @message_id = extract_message_id
  end

  # Run all authentication checks in sequence.
  # Fails fast — on first failure, returns immediately without
  # continuing to subsequent checks.
  #
  # Flow: address → deal, From → user, access check, email auth, dedupe.
  #
  # @return [Result] success if all checks pass; failure with reason otherwise
  def authenticate
    result = lookup_address
    return result unless result.success

    result = lookup_sender
    return result unless result.success

    result = verify_deal_access
    return result unless result.success

    result = verify_email_auth
    return result unless result.success

    result = check_dedupe
    return result unless result.success

    create_ingested_email
  end

  private

  # Step 1: Look up the address to identify the deal.
  # Unknown address = drop silently.
  #
  # @return [Result]
  def lookup_address
    address_local = extract_local_part
    @ingest_address = DealIngestAddress.for_lookup(address_local).first

    if @ingest_address.nil?
      Rails.logger.debug { "DealIngestAuthenticator: unknown address #{address_local}" }
      return Result.new(success: false, reason: "unknown_address")
    end

    @deal = @ingest_address.deal
    Result.new(success: true)
  end

  # Step 2: Look up the sender by From email within the deal's entity.
  # Unknown sender = drop silently.
  #
  # @return [Result]
  def lookup_sender
    sender_email = extract_email(@from)

    if sender_email.blank?
      Rails.logger.debug { "DealIngestAuthenticator: blank sender email" }
      return Result.new(success: false, reason: "no_sender")
    end

    @user = User.find_by(email: sender_email, entity_id: @deal.entity_id)

    if @user.nil?
      Rails.logger.debug { "DealIngestAuthenticator: unknown sender #{sender_email} for entity ##{@deal.entity_id}" }
      return Result.new(success: false, reason: "unknown_sender")
    end

    Result.new(success: true)
  end

  # Step 3: Check if the sender has access to this deal.
  # Access via AccessRight on the deal, or a company_admin role on the entity.
  # No access = drop silently.
  #
  # @return [Result]
  def verify_deal_access
    has_access = AccessRight.exists?(owner: @deal, user: @user) ||
                 @user.has_role?(:company_admin, @deal.entity)

    unless has_access
      Rails.logger.debug { "DealIngestAuthenticator: user ##{@user.id} has no access to deal ##{@deal.id}" }
      return Result.new(success: false, reason: "no_deal_access")
    end

    Result.new(success: true)
  end

  # Step 4: Check SPF/DKIM/DMARC results from the email headers.
  # SendGrid includes these in the raw headers string as
  # Received-SPF and Authentication-Results headers.
  #
  # In MVP, we check for explicit failures only — if the headers
  # are missing (e.g. in development), we let it through.
  #
  # @return [Result]
  def verify_email_auth
    return Result.new(success: true) if @headers.blank?

    spf_fail = @headers.match?(/Received-SPF:\s*fail/i)
    dkim_fail = @headers.match?(/dkim=fail/i)
    dmarc_fail = @headers.match?(/dmarc=fail/i)

    if spf_fail || dkim_fail || dmarc_fail
      Rails.logger.debug { "DealIngestAuthenticator: email auth failed — SPF=#{spf_fail}, DKIM=#{dkim_fail}, DMARC=#{dmarc_fail}" }
      return Result.new(success: false, reason: "email_auth_failed")
    end

    Result.new(success: true)
  end

  # Step 5: Dedupe on RFC-822 Message-ID.
  # Prevents double-posting when SendGrid redelivers (FR-15).
  #
  # @return [Result]
  def check_dedupe
    if @message_id.present? && AgentIngestedEmail.exists?(message_id: @message_id)
      Rails.logger.debug { "DealIngestAuthenticator: duplicate message_id #{@message_id}" }
      return Result.new(success: false, reason: "duplicate")
    end

    Result.new(success: true)
  end

  # All checks passed — create the AgentIngestedEmail and enqueue processing.
  #
  # @return [Result]
  def create_ingested_email
    email_body = @params[:html].presence || @params[:text]

    ingested = AgentIngestedEmail.create!(
      deal: @deal,
      sender_user: @user,
      message_id: @message_id || SecureRandom.uuid,
      raw_payload: email_body,
      received_at: Time.current,
      status: "pending"
    )

    ProcessDealIngestJob.perform_later(ingested.id)

    Rails.logger.debug { "DealIngestAuthenticator: created AgentIngestedEmail ##{ingested.id} for deal ##{@deal.id}" }
    Result.new(success: true)
  end

  # Extract the local part from the To field.
  # Handles formats like "42@dev.caphive.app"
  # and "Some Name <series-b-2026@dev.caphive.app>".
  #
  # @return [String, nil]
  def extract_local_part
    email = extract_email(@to)
    email&.split("@")&.first
  end

  # Extract a bare email address from a field that may include
  # a display name (e.g. "John Doe <john@example.com>" → "john@example.com").
  #
  # @param field [String] raw email field from SendGrid
  # @return [String, nil] lowercase email address
  def extract_email(field)
    return nil if field.blank?

    match = field.match(/<([^>]+)>/)
    (match ? match[1] : field.strip).downcase
  end

  # Extract Message-ID from SendGrid's raw headers string.
  #
  # @return [String, nil]
  def extract_message_id
    @headers&.match(/Message-ID:\s*<([^>]+)>/i)&.[](1)
  end
end
