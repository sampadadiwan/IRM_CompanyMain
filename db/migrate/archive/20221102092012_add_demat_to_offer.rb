class AddDematToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :demat, :string, limit: 20
    add_column :offers, :city, :string, limit: 20
    add_column :interests, :demat, :string, limit: 20
    add_column :interests, :city, :string, limit: 20
  end
end
