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
