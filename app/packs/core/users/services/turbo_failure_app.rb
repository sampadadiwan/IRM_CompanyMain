# Devise failure app that is aware of Turbo Frame requests.
#
# When a session expires mid-page, the next request is often a Turbo Frame
# fetch (identified by the Turbo-Frame header). Devise's default failure app
# would store that frame endpoint as the return-to location, so after
# re-authenticating the user would land on a bare partial rendered standalone.
# Storing the referer (the full page the frame lived on) returns them to the
# page they were actually looking at.
class TurboFailureApp < Devise::FailureApp
  private

  # Devise only stores a return-to location for GET requests, so an expired
  # form submission inside a frame (a POST) would store nothing and dump the
  # user on the root page after re-login. For frame requests the referer is
  # always a safe GET page URL, so store it regardless of the request method.
  def store_location!
    return super unless turbo_frame_request? && request.referer.present?

    store_location_for(scope, attempted_path) unless http_auth?
  end

  # Devise stores this path in the session for after_sign_in_path_for.
  def attempted_path
    return super unless turbo_frame_request? && request.referer.present?

    # Only keep path + query (never scheme/host) so the stored location can't
    # redirect off-site via a spoofed Referer header.
    URI.parse(request.referer).request_uri
  rescue URI::InvalidURIError
    super
  end

  def turbo_frame_request?
    request.headers["Turbo-Frame"].present?
  end
end
