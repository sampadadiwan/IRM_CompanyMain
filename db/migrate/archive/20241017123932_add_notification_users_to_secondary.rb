class AddNotificationUsersToSecondary < ActiveRecord::Migration[7.1]
  def change
    add_column :secondary_sales, :notification_employee_ids, :string
    add_reference :interests, :status_updated_by, null: true, foreign_key: { to_table: :users }
    add_column :interests, :status_updated_at, :datetime
    # remove_column :secondary_sales, :cmf_allocation_percentage
  end
end
