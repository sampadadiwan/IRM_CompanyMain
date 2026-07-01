# frozen_string_literal: true

# Receives AWS SNS POSTs for SES Bounce/Complaint events (see docs/features/
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

  # POST /ses_notifications
  def create
    case @sns_message["Type"]
    when "SubscriptionConfirmation"
      confirm_subscription
    when "Notification"
      ProcessSesNotificationJob.perform_later(@sns_message["Message"])
    when "UnsubscribeConfirmation"
      Rails.logger.info("SNS unsubscribe confirmation received for topic #{@sns_message['TopicArn']}")
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
