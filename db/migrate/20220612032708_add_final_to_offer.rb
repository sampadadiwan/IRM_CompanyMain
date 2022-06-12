class AddFinalToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :acquirer_name, :string
    add_column :offers, :verified, :boolean, default: false
    add_column :offers, :comments, :text
  end
end
