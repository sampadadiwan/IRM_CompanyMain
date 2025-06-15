Doorkeeper::OpenidConnect.configure do
  issuer ENV["BASE_URL"]

  signing_key Rails.application.credentials.oidc_private_key

  subject_types_supported [:public]

  subject do |resource_owner, _application|
    # The unique identifier for the user
    resource_owner.id.to_s
  end

  resource_owner_from_access_token do |access_token|
    User.find_by(id: access_token.resource_owner_id)
  end

  discovery_url_options do |request|

    base_url = ENV["BASE_URL"]
    # set the protocol based on the base_url protocol
    protocol = base_url.start_with?("https") ? :https : :http
    {
      authorization: { protocol: }, # Or :http
      token: { protocol: }, # Or :http
      revocation: { protocol: }, # Or :http
      introspection: { protocol: }, # Or :http
      userinfo: { protocol: }, # Or :http
      jwks: { protocol: }, # Or :http
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
