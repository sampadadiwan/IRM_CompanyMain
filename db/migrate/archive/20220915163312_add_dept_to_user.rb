class AddDeptToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :dept, :string, limit: 20
  end
end
