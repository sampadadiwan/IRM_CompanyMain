class AddCallCodeToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :call_code, :string, limit:3, default: "91"
  end
end
