# M12 (OWASP review 2026-11): count failed sign-ins for the "Security — failed sign-ins" alert (SecurityMetrics).
#
# Warden calls before_failure for every refused authentication, including a signed-out user simply opening a page,
# so only a POST to a sign-in endpoint (web form, API token sign-in) counts. The reason label is Devise's failure
# message (:invalid, :not_found_in_database, :locked, …), a closed set — never the email typed.
# The path is opts[:attempted_path]: Warden has already rewritten PATH_INFO to "/unauthenticated" for the failure
# app when this runs. Registered once at boot; SecurityMetrics is looked up when a failure happens.
#
# M11 (OWASP review 2026-11, security-event-trail S2a): the same hook records the website password failure in the
# security event trail — one filter, so the counter and the trail always agree on what a failed sign-in is. Only the
# website form (POST /users/sign_in): an expired session landing here records nothing (E5), and the API token
# endpoint records its own failures in Users::TokensController (S1g). The typed email is handed on only to be
# digested and looked up off the request thread (SecurityEvent.write!); SecurityEvents.record never raises (E49).
Warden::Manager.before_failure do |env, opts|
  post = env["REQUEST_METHOD"] == "POST"
  path = opts[:attempted_path].to_s.split("?").first
  SecurityMetrics.event(:sign_in_failed, reason: opts[:message]) if post && path.to_s.match?(%r{/users/(?:tokens/)?sign_in\z})

  # M11 S2a / E1–E4 — reason = Devise's message (:invalid, :locked, :inactive)
  if post && path.to_s.end_with?("/users/sign_in")
    begin
      # Reading the form here, not in the recorder, so it is inside this rescue too
      request = ActionDispatch::Request.new(env)
      email = request.POST.dig("user", "email")
      SecurityEvents.record("sign_in.failed", door: "web_password", outcome: :failure, actor: nil, request:,
                                              email:, details: { reason: opts[:message] })
    rescue StandardError => e
      # Never let the trail change the failure page the user sees (E49)
      Rails.logger.warn("[security_event] warden_hook_failed #{e.class}")
    end
  end
end
