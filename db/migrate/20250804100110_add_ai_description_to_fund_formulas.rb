# This migration adds a new text column `ai_description` to the `fund_formulas` table.
# This column will store the AI-generated explanations for each fund formula.
# The `unless column_exists?` check ensures that the migration is idempotent and
# can be run multiple times without causing an error if the column already exists.
class AddAiDescriptionToFundFormulas < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:fund_formulas, :ai_description)
      add_column :fund_formulas, :ai_description, :text
    end
  end
end
