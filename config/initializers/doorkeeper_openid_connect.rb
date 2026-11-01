Doorkeeper::OpenidConnect.configure do
  issuer ENV.fetch("BASE_URL", nil)

  signing_key Rails.application.credentials.oidc_private_key

  subject_types_supported [:public]

  # RFC 7591 Dynamic Client Registration — allows AI clients (Claude, ChatGPT, Gemini)
  # to self-register as OAuth applications at POST /oauth/registration.
  # Users only need to paste the MCP URL; no manual Client ID / Secret entry required.
  # The gem auto-mounts the registration endpoint and advertises it via
  # registration_endpoint in /.well-known/oauth-authorization-server metadata.
  dynamic_client_registration true

  # M2 / N5 — registration was open to any redirect URI and any name, so anyone could register a
  # client called "Claude" (or "CapHive Mail Add-in" with the out-of-band URI) and phish a consent.
  # Now the redirect URIs must belong to one kind in config/mcp_clients.yml and reserved names are
  # refused (McpClientRegistry). Runs inside the gem's DynamicClientRegistrationController
  # (instance_exec), so `params` and `render` are the controller's. A refusal renders RFC 7591's
  # 400 itself — the before_action then halts because a response was rendered — rather than
  # returning false, which the gem would answer with a misleading 401 invalid_token.
  # The endpoint is also throttled per IP (config/initializers/rack_attack.rb, oauth_registration/ip).
  # docs/security/security_review_2026_10.md "Authentication and session — Medium / Low", M2.
  authorize_dynamic_client_registration do
    refusal = McpClientRegistry.registration_refusal(name: params[:client_name], redirect_uris: params[:redirect_uris])
    if refusal
      Rails.logger.warn("[OAuth registration] refused #{params[:client_name].inspect} #{Array(params[:redirect_uris]).inspect}: #{refusal.error}")
      render json: { error: refusal.error, error_description: refusal.description }, status: :bad_request
    end
    true
  end

  subject do |resource_owner, _application|
    # The unique identifier for the user
    resource_owner.id.to_s
  end

  resource_owner_from_access_token do |access_token|
    User.find_by(id: access_token.resource_owner_id)
  end

  discovery_url_options do |_request|
    base_url = ENV.fetch("BASE_URL", nil)
    # set the protocol based on the base_url protocol
    protocol = base_url.start_with?("https") ? :https : :http
    {
      authorization: { protocol: }, # Or :http
      token: { protocol: }, # Or :http
      revocation: { protocol: }, # Or :http
      introspection: { protocol: }, # Or :http
      userinfo: { protocol: }, # Or :http
      jwks: { protocol: }, # Or :http
      dynamic_client_registration: { protocol: }
    }
  end

  auth_time_from_resource_owner do |resource_owner|
    # Return a timestamp indicating the last authentication time
    # This can be `resource_owner.current_sign_in_at` or similar
    resource_owner.respond_to?(:current_sign_in_at) ? resource_owner.current_sign_in_at.to_i : Time.current.to_i
  end

  claims do
    claim :email, response: %i[id_token user_info] do |resource_owner, _scopes, _token|
      resource_owner.email
    end

    claim :name, response: %i[id_token user_info] do |resource_owner, _scopes, _token|
      "#{resource_owner.first_name} #{resource_owner.last_name}"
    end
  end
end
