class ChangeStatusDataType < ActiveRecord::Migration[7.1]
  def change
    rename_column :deal_activities, :status, :status_temp

    add_column :deal_activities, :status, :string, default: 'incomplete'

    incomplete = DealActivity.where(completed: "No")
    incomplete.update_all(status: 'incomplete')

    complete = DealActivity.where(completed: "Yes")
    complete.update_all(status: 'complete')

    templates = DealActivity.where(status_temp: 'Template')
    templates.update_all(status: 'template')
  end
end
