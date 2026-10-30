# One Zoho Sign account a call is made on: CapHive's platform account (from credentials) or a
# company's own connection. ZohoSignClient takes one of these; it never chooses the account itself.
ZohoSignAccount = Data.define(:region, :client_id, :client_secret, :refresh_token, :webhook_secret, :connection) do
  # CapHive's default account. Its Zoho org is in India, hence the "in" default region.
  def self.platform
    credentials = Rails.application.credentials
    new(region: ENV.fetch("ZOHO_REGION", "in"), client_id: credentials[:ZOHO_CLIENT_ID], client_secret: credentials[:ZOHO_CLIENT_SECRET],
        refresh_token: credentials[:ZOHO_REFRESH_TOKEN], webhook_secret: credentials[:ZOHO_WEBHOOK_SECRET], connection: nil)
  end

  # The account every Zoho action on this document uses (the cutover, like Digio's): the company's
  # own account for documents sent at or after it connected (H5, E10), CapHive's for documents sent
  # before (E9, E11) and for companies without a connection. An unsent document goes as if sent now.
  def self.for_document(doc)
    connection = ZohoSignConnection.find_by(entity_id: doc.entity_id)
    return platform if connection.nil?
    return connection.account if doc.sent_for_esign_date.nil?

    doc.sent_for_esign_date >= connection.connected_at ? connection.account : platform
  end

  # The account a document of this entity would be sent on right now.
  def self.for_entity(entity)
    ZohoSignConnection.find_by(entity_id: entity.id)&.account || platform
  end

  def platform?
    connection.nil?
  end

  # Any credential change gives a new key, so a token issued for old credentials is never reused.
  def token_cache_key
    "zoho_sign_access_token/#{region}/#{client_id}/#{Digest::SHA256.hexdigest(refresh_token.to_s)}"
  end

  # Keeps secrets out of logs, error reports and consoles.
  def inspect
    "#<ZohoSignAccount region=#{region} client_id=#{client_id} #{platform? ? 'platform' : "connection=#{connection.id}"}>"
  end
  alias_method :to_s, :inspect
end
