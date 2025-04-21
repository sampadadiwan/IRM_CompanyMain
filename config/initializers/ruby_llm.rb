RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials["OPENAI_API_KEY"],
                          config.gemini_api_key = Rails.application.credentials["GOOGLE_GEMINI_API_KEY"]
end
