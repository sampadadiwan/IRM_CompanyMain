# Refreshes RubyLLM's model registry from the provider APIs (new/updated model
# ids, context windows, pricing, etc.) and saves it to models.json, then syncs
# the ruby_llm_models table so the app's model pickers see the same data.
# Usage:
#   rake irm:ruby_llm:refresh_models
namespace :irm do
  namespace :ruby_llm do
    desc "Refresh and save the latest models available to RubyLLM"
    task refresh_models: :environment do
      RubyLLM.configure do |config|
        config.openai_api_key = Rails.application.credentials["OPENAI_API_KEY"]
        config.gemini_api_key = Rails.application.credentials["GOOGLE_GEMINI_API_KEY"]
        config.anthropic_api_key = Rails.application.credentials["ANTHROPIC_API_KEY"]
      end

      puts "Refreshing RubyLLM models from provider APIs..."
      # RubyLLM 2.x: refresh also persists the registry to its store, the ruby_llm_models
      # table (what Model.save_to_database did in 1.x).
      RubyLLM.models.refresh
      # Export to model_registry_file too: config/initializers/ruby_llm.rb loads it at boot.
      RubyLLM.models.save_to_json
      puts "Saved #{RubyLLM.models.all.size} models to #{RubyLLM.config.model_registry_file}"
      puts "Synced #{RubyLLM::ActiveRecord::Model.count} models into the database"
    end
  end
end
