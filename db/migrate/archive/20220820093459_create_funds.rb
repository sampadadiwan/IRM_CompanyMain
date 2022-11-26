class CreateFunds < ActiveRecord::Migration[7.0]
  def change
    create_table :funds do |t|
      t.string :name
      t.decimal :committed_amount_cents, precision: 20, scale: 2, default: "0.0"
      t.text :details
      t.decimal :collected_amount_cents, precision: 20, scale: 2, default: "0.0" 
      t.references :entity, null: false, foreign_key: true
      t.string :tag_list

      t.timestamps
    end
  end
end
