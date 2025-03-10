Rails.application.config.session_store :cookie_store, 
  key: '_caphive_session', 
  domain: :all, 
  tld_length: 2, 
  expire_after: 30.minutes, 
  secure: !Rails.env.local?, 
  httponly: true 
