class AddEnableAiCommentaryToFunds < ActiveRecord::Migration[8.1]
  def change
    add_column :funds, :enable_ai_commentary, :boolean, default: true, null: false
  end
end
