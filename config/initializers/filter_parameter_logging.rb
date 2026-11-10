# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw email secret token _key crypt salt certificate otp ssn cvv cvc
  signed_id
]
# LP mobile app sign-in: the one-time code and the signed 2FA challenge (token / *_token are
# already covered by "token" above). Exact match for "code" — a partial match would also hide
# call_code, country codes and every other *_code param in the logs.
Rails.application.config.filter_parameters += [/\Acode\z/, :challenge]
# E8: the Zoho Self Client grant code redeemed on the company's Zoho eSign panel (client_secret is
# already covered by "secret" above).
Rails.application.config.filter_parameters += [:grant_code]
# L8-H / L8-1 (docs/security/security_review_2026_10.md, L8): KYC and bank PII, shown as [FILTERED]
# in request logs, exception mail and ActiveRecord #inspect (Rails copies this list into
# ActiveRecord::Base.filter_attributes). Symbols match as substrings, so the short keys are anchored
# regexps: a bare :pan would also hide company_name, company_id and every other *pan* key, and a
# bare :ifsc / :birth_date would not stay confined to the fields that hold the value.
#   \Apan\z        — the PAN column on investors / entities, not company_*
#   \Aifsc         — ifsc_code (and ifsc), not unrelated keys that merely contain the letters
#   \Abirth_date\z — the date of birth, not e.g. birth_date_verified flags
# The remaining keys are distinctive enough to match as substrings (aadhaar_number, passport_no, ...).
# M1 (OWASP 2026-11): case-insensitive. The column is "PAN" on investor_kycs, offers, interests, kyc_data and
# aml_reports, and "IFSC_code" too; a Regexp filter matches case-sensitively, so the L8 filters left both in
# every KYC submit's log line and in exception emails.
Rails.application.config.filter_parameters += [
  /\Apan\z/i, /\Aifsc/i, /\Abirth_date\z/,
  :bank_account_number, :aadhaar, :pan_card_data, :address_proof_data, :bank_routing_info,
  :virtual_bank_account, :passport
]

# M2 (OWASP 2026-11): request credentials in exception emails. The email's Environment section prints
# request.filtered_env, which these filters apply to, and none of them matched the cookie or bearer token, so a
# reader of the error inbox could take over the session (or 30-day API token) of whoever hit the error.
#   HTTP_COOKIE / HTTP_AUTHORIZATION — the raw headers
#   rack.request.cookie_* / action_dispatch.cookies / rack.session — the same values, parsed
#   signed_id — magic-link and shared-link tokens in params (also hidden from request logs)
Rails.application.config.filter_parameters += [
  /\AHTTP_COOKIE\z/, /\AHTTP_AUTHORIZATION\z/, /\Arack\.request\.cookie_(hash|string)\z/,
  /\Aaction_dispatch\.cookies\z/, /\Arack\.session\z/, :signed_id
]

# L8-H — the list above reaches ActiveRecord #inspect only through Rails' "set_filter_attributes"
# on_load hook, which copies config.filter_parameters as they stand when ActiveRecord::Base loads.
# Here that is at Bundler.require time (devise-api's `Devise::Api::Token < ActiveRecord::Base`),
# before any config/initializers run, so the copy was empty and #inspect printed PAN, passwords
# and every other key in clear. Re-sync once every initializer has added its keys.
Rails.application.config.after_initialize do
  ActiveRecord::Base.filter_attributes |= Rails.application.config.filter_parameters
end
