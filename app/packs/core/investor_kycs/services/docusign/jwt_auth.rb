require 'yaml'
require 'jwt'
require 'net/http'
require 'uri'
require 'json'

module JwtAuth
  class JwtCreator
    include ApiCreator

    attr_reader :api_client, :state

    def initialize
      @client_module = DocuSign_eSign
      @scope = 'signature impersonation'
      host = Rails.env.production? ? "account.docusign.com" : "account-d.docusign.com"
      @api_client = create_initial_api_client(host: host, client_module: @client_module, debugging: false)
    end

    # @return [String] The access token string on success; raises an exception if JWT is invalid or if consent is required
    def check_jwt_token(entity_id)
      # Check if the access token is already cached
      access_token = Rails.cache.read("docusign_access_token_#{entity_id}")
      if access_token.present?
        ttl = Rails.cache.read("docusign_access_token_ttl_#{entity_id}")
        Rails.logger.info { "Found access token in cache with remaining TTL: #{ttl} seconds" }
        return access_token
      end

      Rails.logger.info "Fetching Docusign access token"

      # docusign gem method expects a file path to the RSA private key
      tmp_file = Tempfile.new(['docusign_rsa_key', '.pem'])
      begin
        # docusign_esign: POST /oauth/token
        # This endpoint enables you to exchange an authorization code or JWT token for an access token.
        # https://developers.docusign.com/platform/auth/reference/obtain-access-token
        tmp_file.write(DocusignEsignHelper::DOCUSIGN_RSA_PRIVATE_KEY)
        tmp_file.close
        rsa_pk = tmp_file.path.to_s
        token = api_client.request_jwt_user_token(
          DocusignEsignHelper::DOCUSIGN_INTEGRATION_KEY,
          DocusignEsignHelper::DOCUSIGN_USER_ID,
          rsa_pk,
          3600,
          @scope
        )
      rescue OpenSSL::PKey::RSAError => e
        Rails.logger.error e.inspect
        raise "Please add your private RSA key to: #{rsa_pk}" if File.read(rsa_pk).starts_with? '{RSA_PRIVATE_KEY}'

        raise e
      rescue @client_module::ApiError => e
        Rails.logger.warn e.inspect

        raise "No response body received from DocuSign API" if e.response_body.nil?

        body = JSON.parse(e.response_body)

        if body['error'] == 'consent_required'
          raise "Consent required: #{body}"
        else
          details = <<~TXT
            See: https://support.docusign.com/articles/DocuSign-Developer-Support-FAQs#Troubleshoot-JWT-invalid_grant
            or https://developers.docusign.com/esign-rest-api/guides/authentication/oauth2-code-grant#troubleshooting-errors
            or try enabling `configuration.debugging = true` in the initialize method above for more logging output
          TXT
          raise "JWT response error: `#{body}`. #{details}"
        end
      else
        # Cache the token with a 59-minute expiration (1 minute before actual expiry)
        expiration_time = token.expires_in.to_i - 60
        Rails.cache.write("docusign_access_token_#{entity_id}", token.access_token, expires_in: expiration_time.seconds)
        Rails.cache.write("docusign_access_token_ttl_#{entity_id}", expiration_time, expires_in: expiration_time.seconds)
        Rails.logger.debug { "Access token cached with #{expiration_time} seconds expiration" }
        token.access_token
      ensure
        tmp_file.close!
      end
    end
  end
end
