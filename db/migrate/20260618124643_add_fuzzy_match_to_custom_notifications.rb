class AddFuzzyMatchToCustomNotifications < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:custom_notifications, :fuzzy_match)
      add_column :custom_notifications, :fuzzy_match, :boolean, default: false, null: false
    end
  end
end
