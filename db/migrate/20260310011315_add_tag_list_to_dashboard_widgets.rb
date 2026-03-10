class AddTagListToDashboardWidgets < ActiveRecord::Migration[8.1]
  def change
    add_column :dashboard_widgets, :tag_list, :string, limit: 20
  end
end
