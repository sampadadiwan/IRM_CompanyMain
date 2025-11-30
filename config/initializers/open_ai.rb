OpenAI.configure do |config|
  config.access_token = Rails.application.credentials["OPENAI_API_KEY"]
  config.log_errors = Rails.env.development? # Useful for debugging
end
