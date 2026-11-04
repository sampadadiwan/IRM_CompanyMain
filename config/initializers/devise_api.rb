# frozen_string_literal: true

# devise-api's bearer-token endpoints (/users/tokens/*, Users::TokensController).
#
# M6 — account enumeration through the token API:
# * sign_in answered an unknown email with 400 "Email is invalid" and a wrong password with 401,
#   and named a locked account ("Your account is locked", plus failed-attempt counts). paranoid
#   makes all three the same 401 "Email or password is invalid" with no account details.
# * sign_up was live: anyone could create a user over JSON. Nothing uses it (users are created by
#   their firm or by the onboarding import), so it is switched off (400 sign_up_disabled).
# Sign-in and refresh stay as they are; they are used by the onboarding skill and runbooks.
# Throttled per IP and per email in config/initializers/rack_attack.rb (tokens/sign_in/*).
#
# docs/security/security_review_2026_10.md "Authentication and session — Medium / Low", M6.
Devise.api.configure do |api|
  # M6-1 — an unknown email answers exactly like a wrong password
  api.paranoid = true
  # M6-1 — no lockable / confirmable details in the error either
  api.error_response.verbose_account_state = false
  # M6-2 — no self-service accounts through the API
  api.sign_up.enabled = false
end
