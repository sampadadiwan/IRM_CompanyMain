class AddCurrRoleToReport < ActiveRecord::Migration[7.1]
  def change
    add_column :reports, :curr_role, :string, limit: 10, default: "employee"
  end
end
