# The Zoho eSign panel on the company page: connect, reconnect, verify, disconnect and the webhook
# secret. Every action answers with the panel re-rendered in place.
class ZohoSignConnectionsController < ApplicationController
  before_action :set_connection

  # H2, E3, E4, E5, X3, X4
  def create
    render_panel(setup.connect(@entity, connection_params, current_user))
  end

  # H14, E6, X5 (reconnect)
  def update
    render_panel(setup.reconnect(@connection, connection_params))
  end

  # H16, X6
  def destroy
    render_panel(setup.disconnect(@connection))
  end

  # H4, X7
  def verify
    render_panel(setup.verify(@connection))
  end

  # H3
  def reveal_webhook_secret
    secret = @connection.reveal_webhook_secret!
    render_panel(ZohoSignConnectionSetup::Result.new(secret.present?, nil, nil, @connection), secret:)
  end

  # E7
  def regenerate_webhook_secret
    secret = @connection.regenerate_webhook_secret!
    render_panel(ZohoSignConnectionSetup::Result.new(true, nil, "New webhook secret created - paste it into the company's Zoho webhook.", @connection), secret:)
  end

  private

  # X1, X2: the entity comes from the URL and the policy checks it; no connection id is ever taken
  # from params.
  def set_connection
    @entity = Entity.find(params[:entity_id])
    @connection = ZohoSignConnection.find_by(entity_id: @entity.id)
    authorize(@connection || ZohoSignConnection.new(entity: @entity))
    raise ActiveRecord::RecordNotFound if @connection.nil? && action_name != "create"
  end

  def connection_params
    params.require(:zoho_sign_connection).permit(:region, :client_id, :client_secret, :grant_code)
  end

  def setup
    ZohoSignConnectionSetup.new
  end

  def render_panel(result, secret: nil)
    connection = ZohoSignConnection.find_by(entity_id: @entity.id)
    form = result.success? ? nil : result.connection
    render turbo_stream: turbo_stream.replace("zoho_sign_connection_panel", partial: "zoho_sign_connections/panel",
                                                                            locals: { entity: @entity, connection:, form:, result:, secret: }),
           status: result.success? ? :ok : :unprocessable_content
  end
end
