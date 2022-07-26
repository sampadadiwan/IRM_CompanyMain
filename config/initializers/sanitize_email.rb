SanitizeEmail::Config.configure do |config|
  config[:sanitized_to] = ENV['SANDBOX_EMAILS']
  # config[:sanitized_cc] =         'cc@sanitize_email.org'
  # config[:sanitized_bcc] =        'bcc@sanitize_email.org'
  # run/call whatever logic should turn sanitize_email on and off in this Proc:
  config[:activation_proc] = proc { |message|
    %w[development staging sandbox production].include?(Rails.env) && message.subject.index("Error").nil?
  }
  # config[:use_actual_email_prepended_to_subject] = true         # or false
  config[:use_actual_environment_prepended_to_subject] = true   # or false
  config[:use_actual_email_as_sanitized_user_name] = true       # or false
end
