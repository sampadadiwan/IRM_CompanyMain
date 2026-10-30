# Zoho Sign webhooks for a company's own Zoho account (one address per company, design card ⑥).
# Authenticated by the unguessable token in the address plus the connection's HMAC secret instead
# of a session; verified updates are acknowledged at once and applied by ZohoWebhookJob.
class ZohoSignWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, :authenticate_user!, :set_current_entity
  skip_after_action :verify_authorized

  def create
    connection = ZohoSignConnection.find_by(webhook_token: params[:token].to_s)
    # X21: not an address we gave anyone
    return head :not_found if connection.nil?

    # X18 (missing), E7 (old secret after a regenerate)
    unless ZohoEsignHelper.verify_signature(request.raw_post, request.headers["X-ZS-WEBHOOK-SIGNATURE"], connection.webhook_secret)
      Rails.logger.warn("Zoho Sign webhook signature verification failed for connection #{connection.id}")
      return render json: "Invalid signature", status: :unauthorized
    end

    # H8: the panel's "Last update" - proves the webhook works (no audit entry for it)
    connection.update_column(:last_webhook_at, Time.current)
    ZohoWebhookJob.perform_later(connection.id, request.raw_post)
    render json: "Ok"
  end
end
