class AddFullNameToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :full_name, :string, limit: 100
    safety_assured { remove_column :offers, :first_name, :string }
    safety_assured { remove_column :offers, :middle_name, :string }
    safety_assured { remove_column :offers, :last_name, :string }
  end
end
