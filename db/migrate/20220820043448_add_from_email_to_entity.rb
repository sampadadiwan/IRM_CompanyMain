class AddFromEmailToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :from_email, :string, limit: 100
  end
end
