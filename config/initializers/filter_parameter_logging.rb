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
Rails.application.config.filter_parameters += [
  /\Apan\z/, /\Aifsc/, /\Abirth_date\z/,
  :bank_account_number, :aadhaar, :pan_card_data, :address_proof_data, :bank_routing_info,
  :virtual_bank_account, :passport
]
