class CreateModels < ActiveRecord::Migration[8.0]
  def change
    create_table :models, if_not_exists: true do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff

      t.json :modalities
      t.json :capabilities
      t.json :pricing
      t.json :metadata

      t.timestamps

      t.index [:provider, :model_id], unique: true
      t.index :provider
      t.index :family

    end

    # Load models from JSON
    say_with_time "Loading models from models.json" do
      # RubyLLM.models.refresh!
      # RubyLLM.models.save_to_json  # Saves to configured model_registry_file (v1.9.0+)
      # Model.save_to_database
    end
  end
end
