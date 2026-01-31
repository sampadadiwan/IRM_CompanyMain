class AddApprovalTrackingToKpis < ActiveRecord::Migration[8.1]
  def change
    add_column :kpis, :approved_by_user_id, :bigint
    add_column :kpis, :approved_at, :datetime
  end
end
