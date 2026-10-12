# Evergreen scenarios move the clock with travel_to (dealing dates, cut-offs, notice). The session
# cookie's expiry (session_store expire_after: 60.minutes) is stamped from that travelled clock, so a
# date before today makes the browser drop the cookie at once and the user is signed out. While an
# evergreen scenario has travelled, the cookie is written as a browser-session cookie (no expiry).
module EvergreenSessionCookie
  class << self
    attr_accessor :travelling
  end

  def set_cookie(request, session_id, cookie)
    cookie = cookie.except(:expires) if EvergreenSessionCookie.travelling && cookie.is_a?(Hash)
    super
  end
end

ActionDispatch::Session::CookieStore.prepend(EvergreenSessionCookie)

After { EvergreenSessionCookie.travelling = false }
