class ChangeCompletedForDealActivities < ActiveRecord::Migration[7.0]
  def change
    change_column :deal_activities, :completed, :string, limit: 5 
  end
end
