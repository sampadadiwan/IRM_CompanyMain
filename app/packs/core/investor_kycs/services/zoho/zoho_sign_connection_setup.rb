# Connect, reconnect, verify and disconnect a company's own Zoho Sign account (design card ①).
# Zoho is always called before anything is written, so a refusal saves nothing (X3, X4, X5).
class ZohoSignConnectionSetup
  Result = Struct.new(:success, :errors, :message, :connection) do
    def success? = success
  end

  RECONNECT_MESSAGE = "Zoho rejected the stored credentials. Reconnect with a new grant code.".freeze

  # H2, E3, E4, E5, X3, X4. The grant code is exchanged and never stored.
  def connect(entity, params, user)
    connection = ZohoSignConnection.new(entity:, connected_by: user, region: params[:region], client_id: params[:client_id].to_s.strip,
                                        client_secret: params[:client_secret])
    return failure(connection) unless required_fields?(connection, params, secret: params[:client_secret])

    connection.refresh_token = ZohoSignClient.exchange_grant_code(region: connection.region, client_id: connection.client_id,
                                                                  client_secret: connection.client_secret, code: params[:grant_code].strip)
    connection.save!
    success(connection, "Connected — documents sent from now on use #{entity.name}'s Zoho account (#{connection.region_name}).")
  rescue ZohoSignClient::Error => e
    failure(connection, message_for(e, connection.region))
  rescue ActiveRecord::RecordNotUnique
    # E5: a second Connect for the same company (double click) loses to the unique entity_id index
    failure(ZohoSignConnection.find_by(entity_id: entity.id), "This company is already connected to Zoho.")
  end

  # H14, E6, X5: blank fields keep the stored values; connected_at (the cutover) never changes.
  def reconnect(connection, params)
    form = ZohoSignConnection.new(entity: connection.entity, region: params[:region].presence || connection.region,
                                  client_id: params[:client_id].to_s.strip.presence || connection.client_id,
                                  client_secret: params[:client_secret].presence || connection.client_secret)
    return failure(connection, nil, form) unless required_fields?(form, params, secret: form.client_secret)

    refresh_token = ZohoSignClient.exchange_grant_code(region: form.region, client_id: form.client_id, client_secret: form.client_secret,
                                                       code: params[:grant_code].strip)
    connection.with_lock do
      connection.update!(region: form.region, client_id: form.client_id, client_secret: form.client_secret, refresh_token:,
                         status: :connected, last_error: nil)
    end
    success(connection, "Connected — documents sent from now on use #{connection.entity.name}'s Zoho account (#{connection.region_name}).")
  rescue ZohoSignClient::Error => e
    failure(connection, message_for(e, form.region), form)
  end

  # H4, X7: one read-only call with the stored credentials.
  def verify(connection)
    ZohoSignClient.new(connection.account).list_requests_probe
    connection.update!(status: :connected, last_error: nil, last_verified_at: Time.current)
    success(connection, "Connection verified")
  rescue ZohoSignClient::AuthError => e
    connection.mark_needs_reauth!(e.message)
    failure(connection, RECONNECT_MESSAGE)
  rescue ZohoSignClient::Error
    failure(connection, "Zoho could not be reached. Try again in a few minutes.")
  end

  # H16, X6: refused while documents sent on this account are still out for signature.
  def disconnect(connection)
    out = 0
    connection.with_lock do
      out = connection.documents_out_for_signature.count
      connection.destroy! if out.zero?
    end
    return success(nil, "Disconnected — documents sent from now on use CapHive's Zoho account.") if out.zero?

    failure(connection, "#{out} #{'document'.pluralize(out)} #{out == 1 ? 'is' : 'are'} still out for signature on this account. " \
                        "Wait for them to finish or cancel them first.")
  end

  private

  # E3, E4: every missing field is marked, and nothing is sent to Zoho.
  def required_fields?(connection, params, secret:)
    connection.errors.add(:region, "Pick a Zoho region") unless ZohoSignClient::REGIONS.key?(connection.region.to_s)
    connection.errors.add(:client_id, "is required") if connection.client_id.blank?
    connection.errors.add(:client_secret, "is required") if secret.blank?
    connection.errors.add(:grant_code, "is required") if params[:grant_code].blank?
    connection.errors.empty?
  end

  def message_for(error, region)
    case error
    when ZohoSignClient::AuthError
      case error.reason
      when :invalid_code
        "Zoho did not accept the grant code — it may have expired or already been used. " \
        "Generate a new code in Zoho's API console and try again."
      when :invalid_client
        "Zoho did not recognise this Client ID in the #{ZohoSignClient::REGIONS[region]&.name} region. " \
        "Check the region matches the address of your Zoho account (sign.zoho.com = United States)."
      when :invalid_secret
        "Zoho did not accept the Client Secret. Copy it again from your Self Client in Zoho's API console."
      else
        "Zoho did not accept these credentials. Check the Client ID, Client Secret and region, and generate a new grant code."
      end
    else
      "Zoho could not be reached. Try again in a few minutes."
    end
  end

  def success(connection, message)
    Result.new(true, nil, message, connection)
  end

  def failure(connection, message = nil, form = connection)
    Result.new(false, form&.errors&.full_messages, message, form)
  end
end
