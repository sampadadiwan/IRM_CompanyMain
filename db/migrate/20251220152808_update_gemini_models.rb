class UpdateGeminiModels < ActiveRecord::Migration[8.0]
  def change
    RubyLLM.models.refresh!
    RubyLLM.models.save_to_json
  end
end
