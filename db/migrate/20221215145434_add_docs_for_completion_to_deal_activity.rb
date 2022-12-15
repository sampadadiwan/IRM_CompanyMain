class AddDocsForCompletionToDealActivity < ActiveRecord::Migration[7.0]
  def change
    add_column :deal_activities, :docs_required_for_completion, :boolean, default: false
    add_column :deal_activities, :details_required_for_na, :boolean, default: false
    add_column :entities, :activity_docs_required_for_completion, :boolean, default: false
    add_column :entities, :activity_details_required_for_na, :boolean, default: false
    change_column :deal_activities, :completed, :string, limit: 5, default: "No"
  end
end
