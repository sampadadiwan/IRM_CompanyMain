class AddPanCardToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :pan_card_data, :text
  end
end
