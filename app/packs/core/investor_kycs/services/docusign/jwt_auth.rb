require 'yaml'
require 'jwt'
require 'net/http'
require 'uri'
require 'json'

module JwtAuth
  class JwtCreator
    include ApiCreator

    attr_reader :api_client, :state, :redis

    def initialize
      @client_module = DocuSign_eSign
      @scope = 'signature impersonation'
      @api_client = create_initial_api_client(host: "account-d.docusign.com", client_module: @client_module, debugging: false)
      @redis = Redis.new
    end

    def store_access_token_in_redis(redis, key, access_token, expiration_time)
      redis.setex(key, expiration_time, access_token)
      Rails.logger.debug { "Access token stored in Redis with a #{expiration_time} seconds expiration time" }
    end

    # most straightforward method
    # rubocop:disable Metrics/MethodLength
    def get_docusign_access_token
      # Header
      header = {
        alg: 'RS256',
        typ: 'JWT'
      }

      rsa_private_key = OpenSSL::PKey::RSA.new(DocusignEsignHelper::DOCUSIGN_RSA_PRIVATE_KEY)
      # Body
      current_time = Time.now.to_i
      body = {
        iss: DocusignEsignHelper::DOCUSIGN_INTEGRATION_KEY,
        sub: DocusignEsignHelper::DOCUSIGN_USER_ID,
        aud: 'account-d.docusign.com',
        iat: current_time,
        exp: current_time + 6000,
        scope: 'signature impersonation'
      }

      # Encode the JWT
      token = JWT.encode(body, rsa_private_key, 'RS256', header)

      # Exchange JWT for an access token
      uri = URI.parse("https://account-d.docusign.com/oauth/token")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/x-www-form-urlencoded"
      request.body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=#{token}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      response_data = JSON.parse(response.body)

      if response.code.to_i == 200
        access_token = response_data['access_token']
        Rails.logger.info "Access Token: #{access_token}"
        store_access_token_in_redis(redis, 'docusign_access_token', token.access_token, token.expires_in.to_i - 60) # 60 seconds less than the actual expiration time
        access_token
      else
        error_description = response_data['error_description']
        Rails.logger.error "Error: #{error_description}"
        nil
      end
    end

    # @return [Boolean] `true` if the token was successfully updated, `false` if consent still needs to be grant'ed
    def check_jwt_token
      # Check if the access token is already in Redis
      access_token = redis.get('docusign_access_token')
      # print found with remaining time
      if access_token.present?
        Rails.logger.debug { "Found access token in Redis with remaining time: #{redis.ttl('docusign_access_token')} seconds" }
        return access_token
      end

      Rails.logger.info "Fetching Docusign access token"

      # docusign gem method expects a file path to the RSA private key
      tmp_file = Tempfile.new(['docusign_rsa_key', '.pem'])
      tmp_file.write(DocusignEsignHelper::DOCUSIGN_RSA_PRIVATE_KEY)
      tmp_file.close
      rsa_pk = tmp_file.path.to_s

      begin
        # docusign_esign: POST /oauth/token
        # This endpoint enables you to exchange an authorization code or JWT token for an access token.
        # https://developers.docusign.com/platform/auth/reference/obtain-access-token
        token = api_client.request_jwt_user_token(DocusignEsignHelper::DOCUSIGN_INTEGRATION_KEY, DocusignEsignHelper::DOCUSIGN_USER_ID, rsa_pk, 3600, @scope)
      rescue OpenSSL::PKey::RSAError => e
        Rails.logger.error e.inspect
        raise "Please add your private RSA key to: #{rsa_pk}" if File.read(rsa_pk).starts_with? '{RSA_PRIVATE_KEY}'

        raise e
      rescue @client_module::ApiError => e
        Rails.logger.warn e.inspect

        return false if e.response_body.nil?

        body = JSON.parse(e.response_body)

        if body['error'] == 'consent_required'
          false
        else
          details = <<~TXT
            See: https://support.docusign.com/articles/DocuSign-Developer-Support-FAQs#Troubleshoot-JWT-invalid_grant
            or https://developers.docusign.com/esign-rest-api/guides/authentication/oauth2-code-grant#troubleshooting-errors
            or try enabling `configuration.debugging = true` in the initialize method above for more logging output
          TXT
          raise "JWT response error: `#{body}`. #{details}"
        end
      else
        store_access_token_in_redis(redis, 'docusign_access_token', token.access_token, token.expires_in.to_i)
        token.access_token
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
