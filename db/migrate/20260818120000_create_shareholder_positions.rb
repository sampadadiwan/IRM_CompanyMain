class CreateShareholderPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :shareholder_positions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.references :portfolio_company, foreign_key: { to_table: :investors }
      t.references :fund, foreign_key: true
      t.references :import_upload, foreign_key: true

      t.string :position_type, null: false, limit: 50
      t.decimal :position_amount, precision: 20, scale: 2
      t.decimal :quantity_actual, precision: 20, scale: 2
      # Stores the typed "Fully Dilluted %" from an upload as real percentage points (0-100),
      # so the cap table can use it directly instead of always recomputing % from the Fully
      # Dilluted Quantity - the quantity-based computation is only a fallback for rows that
      # never had a % typed in.
      t.decimal :fully_diluted_percentage, precision: 10, scale: 4

      t.date :position_date
      t.string :round_name
      t.string :category
      t.string :subgroup
      t.string :instrument
      t.string :investor_label

      t.string :status, default: "approved"
      t.bigint :approved_by_user_id
      t.datetime :approved_at

      t.datetime :deleted_at

      t.timestamps
    end

    change_table :shareholder_positions, bulk: true do |t|
      t.index %i[entity_id investor_id fund_id position_date],
              name: "idx_shareholder_positions_entity_investor_fund_as_of"
      t.index :position_date
      t.index :round_name
      t.index :category
      t.index :subgroup
      t.index :instrument
      t.index :investor_label
      t.index :status
      t.index :deleted_at
    end
  end
end
