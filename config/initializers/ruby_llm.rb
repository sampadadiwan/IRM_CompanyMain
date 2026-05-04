RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials["OPENAI_API_KEY"]
  config.gemini_api_key = Rails.application.credentials["GOOGLE_GEMINI_API_KEY"]
  config.use_new_acts_as = true
end

# Force a fresh read of the gem's bundled models.json on every boot.
# Without this, RubyLLM::Models.instance can hold a stale in-memory snapshot
# from before the gem (or its models.json) was last updated, causing
# "Unknown model" errors for models that DO exist in the current JSON.
RubyLLM::Models.instance.load_from_json!
