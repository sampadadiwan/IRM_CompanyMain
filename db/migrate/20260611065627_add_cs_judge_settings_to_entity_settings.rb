# frozen_string_literal: true

# Adds CS agent judge configuration to entity settings.
# cs_judge_enabled: toggle LLM-as-judge scoring on/off (default: on)
# cs_judge_model: override the LLM model used for judging (nullable, falls back to ENV/default)
class AddCsJudgeSettingsToEntitySettings < ActiveRecord::Migration[8.0]
  def change
    add_column :entity_settings, :cs_judge_enabled, :boolean, default: true, null: false
    add_column :entity_settings, :cs_judge_model, :string
  end
end
