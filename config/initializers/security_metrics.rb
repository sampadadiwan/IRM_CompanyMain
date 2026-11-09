# M12 (OWASP review 2026-11): count failed sign-ins for the "Security — failed sign-ins" alert (SecurityMetrics).
#
# Warden calls before_failure for every refused authentication, including a signed-out user simply opening a page,
# so only a POST to a sign-in endpoint (web form, API token sign-in) counts. The reason label is Devise's failure
# message (:invalid, :not_found_in_database, :locked, …), a closed set — never the email typed.
# The path is opts[:attempted_path]: Warden has already rewritten PATH_INFO to "/unauthenticated" for the failure
# app when this runs. Registered once at boot; SecurityMetrics is looked up when a failure happens.
Warden::Manager.before_failure do |env, opts|
  post = env["REQUEST_METHOD"] == "POST"
  path = opts[:attempted_path].to_s.split("?").first
  SecurityMetrics.event(:sign_in_failed, reason: opts[:message]) if post && path.to_s.match?(%r{/users/(?:tokens/)?sign_in\z})
end
