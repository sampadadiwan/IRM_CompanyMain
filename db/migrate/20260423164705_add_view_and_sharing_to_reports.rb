class AddViewAndSharingToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :is_view, :boolean, default: false, null: false
    add_column :reports, :view_target, :string
    add_column :reports, :shared, :boolean, default: false, null: false
    add_column :reports, :last_run_at, :datetime
  end
end
