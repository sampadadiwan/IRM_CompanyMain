# Splits, bonuses and dividends reported by the price provider for Market instruments, waiting for
# a person to confirm (into a Stock Adjustment / portfolio cashflows) or dismiss. provider_ref is
# unique so the same action is never suggested twice. Worked examples H10, E46, E47 — fund-market-data.
class CreateCorporateActionSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :corporate_action_suggestions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investment_instrument, null: false, foreign_key: true
      t.string :kind, limit: 10, null: false
      t.date :ex_date, null: false
      t.decimal :ratio, precision: 12, scale: 8
      t.decimal :amount_per_share_cents, precision: 20, scale: 2
      t.string :currency, limit: 5
      t.string :provider, limit: 20, null: false
      t.string :provider_ref, limit: 100, null: false
      t.string :subject
      t.string :status, limit: 10, null: false, default: "pending"
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.references :stock_adjustment, foreign_key: true
      t.timestamps

      t.index %i[entity_id provider_ref], unique: true, name: "idx_corporate_action_suggestions_ref"
      t.index %i[entity_id status]
    end
  end
end
