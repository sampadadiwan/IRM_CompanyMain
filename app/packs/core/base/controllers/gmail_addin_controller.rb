# Brokers sign-in for the Gmail add-on.
#
# The add-on cannot show a CapHive login form itself: Gmail add-ons render Google's
# CardService widgets, which have no password input type, and the previous build collected
# the user's CapHive password in a plaintext TextInput. That exposed the password on
# screen, bypassed SSO and MFA entirely, and is a standard Marketplace rejection.
#
# Instead the add-on opens this endpoint in a normal browser tab, where the Devise session
# — and therefore any SSO or MFA the tenant uses — works as it does everywhere else. A
# bearer token is minted for the authenticated user and handed back to Apps Script through
# Google's usercallback mechanism, using the state token the add-on generated.
#
# @see docs/modules/mail_addins/mail_addin_review.md
class GmailAddinController < ApplicationController
  # Apps Script hands control back through this host only. Validated strictly, because the
  # redirect carries an access token in its query string — accepting an arbitrary
  # redirect_uri here would be an open redirect that leaks credentials.
  ALLOWED_CALLBACK_HOST = 'script.google.com'.freeze

  skip_after_action :verify_authorized, only: [:oauth_start]

  # Opened in a browser tab by the add-on's sign-in link. authenticate_user! applies, so
  # Devise prompts normally when there is no session.
  def oauth_start
    skip_authorization

    callback = parsed_callback_uri
    if callback.nil?
      render plain: 'Invalid sign-in callback address.', status: :bad_request
      return
    end

    payload = MailAddinToken.payload_for(current_user)
    callback.query = [callback.query.presence, {
      token: payload[:access_token],
      expires_at: payload[:expires_at],
      user_name: payload[:user_name]
    }.to_query].compact.join('&')

    # allow_other_host is required and safe here: the destination has been verified to be
    # Google's Apps Script callback host.
    redirect_to callback.to_s, allow_other_host: true
  end

  private

  # @return [URI::HTTPS, nil] the callback URI when it is a genuine Apps Script callback
  def parsed_callback_uri
    raw = params[:redirect_uri].to_s
    return nil if raw.blank?

    uri = URI.parse(raw)
    return nil unless uri.is_a?(URI::HTTPS)
    # Exact host match, not suffix: "script.google.com.evil.test" must not pass.
    return nil unless uri.host == ALLOWED_CALLBACK_HOST
    return nil unless uri.path.include?('/usercallback')

    uri
  rescue URI::InvalidURIError
    nil
  end
end
