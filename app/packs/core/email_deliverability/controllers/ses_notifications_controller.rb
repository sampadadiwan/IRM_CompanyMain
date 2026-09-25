# frozen_string_literal: true

# Receives AWS SNS POSTs for SES Bounce/Complaint events (see docs/modules/notifications/
# email_bounce_complaint_detection_prd.md). Unauthenticated by necessity — AWS
# cannot authenticate as an app user — so the SNS message signature is the only
# protection here and verification is mandatory, not optional. Mirrors
# UsersSyncController's use of ActionController::API for this class of endpoint
# (external service, no session, no CSRF).
class SesNotificationsController < ActionController::API
  # Reused across requests (not per-request) so its internal signing-cert cache
  # actually avoids re-fetching the AWS PEM over HTTPS on every notification.
  MESSAGE_VERIFIER = Aws::SNS::MessageVerifier.new

  before_action :verify_sns_signature!
  before_action :verify_sns_topic!

  # POST /ses_notifications
  def create
    case @sns_message["Type"]
    when "SubscriptionConfirmation"
      confirm_subscription
    when "Notification"
      ProcessSesNotificationJob.perform_later(@sns_message["Message"])
    when "UnsubscribeConfirmation"
      Rails.logger.info("SNS unsubscribe confirmation received for topic #{@sns_message['TopicArn']}")
    else
      # Signed by SNS and from our topic, but not a type we handle. Logged rather than
      # dropped silently, so an unexpected shape is visible instead of looking like success.
      Rails.logger.warn("Ignoring SNS message of unhandled Type=#{@sns_message['Type'].inspect} (MessageId=#{@sns_message['MessageId']})")
    end

    render json: { status: "ok" }
  end

  private

  def verify_sns_signature!
    raw_body = request.raw_post
    @sns_message = JSON.parse(raw_body)

    unless MESSAGE_VERIFIER.authentic?(raw_body)
      Rails.logger.warn("Rejected SES notification with invalid SNS signature (MessageId=#{@sns_message['MessageId']})")
      render json: { error: "invalid_signature" }, status: :forbidden
    end
  rescue JSON::ParserError
    render json: { error: "invalid_json" }, status: :bad_request
  end

  # A valid SNS signature proves only that SOME SNS topic in SOME AWS account sent this -
  # it does not bind the message to ours. Without this check anyone could subscribe this
  # endpoint to a topic they control (confirm_subscription below would confirm it for them)
  # and then inject Bounce payloads: writing EmailBounceEvent rows and setting bounced_at /
  # bounce_type on any Noticed::Notification whose tracking UUID they guessed.
  #
  # Fails closed. If SES_SNS_TOPIC_ARN is unset nothing is accepted, because an endpoint
  # that cannot tell our topic from a stranger's should not be processing events at all.
  # ses:setup_bounce_tracking prints the value to configure.
  def verify_sns_topic!
    expected = ENV.fetch("SES_SNS_TOPIC_ARN", nil).presence
    if expected.blank?
      Rails.logger.error("Rejected SES notification: SES_SNS_TOPIC_ARN is not configured, so the sending topic cannot be verified")
      return render json: { error: "topic_not_configured" }, status: :forbidden
    end

    return if @sns_message["TopicArn"] == expected

    Rails.logger.warn("Rejected SES notification from unexpected topic #{@sns_message['TopicArn'].inspect} (expected #{expected.inspect})")
    render json: { error: "unexpected_topic" }, status: :forbidden
  end

  def confirm_subscription
    uri = URI(@sns_message["SubscribeURL"])
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
      http.get(uri.request_uri)
    end
    Rails.logger.info("Confirmed SNS subscription for topic #{@sns_message['TopicArn']}")
  rescue StandardError => e
    Rails.logger.error("Failed to confirm SNS subscription for topic #{@sns_message['TopicArn']}: #{e.message}")
  end
end
