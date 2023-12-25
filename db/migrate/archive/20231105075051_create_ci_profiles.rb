class CreateCiProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :ci_profiles do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: true, foreign_key: true
      t.string :title
      t.string :geography, limit: 50
      t.string :stage, limit: 50
      t.string :sector, limit: 50
      t.decimal :fund_size_cents, precision: 20, scale: 2
      t.decimal :min_investment_cents, precision: 20, scale: 2
      t.string :status
      t.string :currency, limit: 3
      t.text :details
      t.bigint :form_type_id
      t.text :properties
      t.text :track_record
      t.bigint :document_folder_id
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :ci_profiles, :deleted_at
  end
end
