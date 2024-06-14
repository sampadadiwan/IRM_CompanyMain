class AddedCardViewAttrsToDeal < ActiveRecord::Migration[7.1]
  def change
    unless column_exists? :deals, :card_view_attrs
      add_column :deals, :card_view_attrs, :json
    end
  end
end
