class AddSyntheticToValuation < ActiveRecord::Migration[8.0]
  def change
    add_column :valuations, :synthetic, :boolean, default: false, null: false
  end
end
