class AddIfscToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :ifsc_code, :string, limit: 20
  end
end
