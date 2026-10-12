# Derivative contracts held by a fund and their events (trade, valuation, settlement, margin,
# exercise, expiry, close-out). Values come from events; ledger entries point back to the event.
# openspec/changes/fund-market-data — design card ⑥. Worked examples H11–H17, E48–E57, X16–X26.
class CreateDerivatives < ActiveRecord::Migration[8.1]
  def change
    create_table :derivative_contracts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.string :contract_type, limit: 20, null: false
      t.boolean :listed, null: false, default: false
      t.string :exchange, limit: 10
      t.string :feed_symbol, limit: 60
      t.string :counterparty_name, limit: 100
      t.references :agreement_document, foreign_key: { to_table: :documents }
      t.string :underlying_type, limit: 15, null: false
      t.references :underlying_instrument, foreign_key: { to_table: :investment_instruments }
      t.string :underlying_name, limit: 30
      t.string :side, limit: 5, null: false
      t.string :option_type, limit: 4
      t.decimal :strike, precision: 20, scale: 8
      t.decimal :forward_rate, precision: 20, scale: 8
      t.decimal :lots, precision: 24, scale: 8
      t.decimal :open_lots, precision: 24, scale: 8
      t.decimal :lot_size, precision: 24, scale: 8
      t.decimal :notional_cents, precision: 20, scale: 2
      t.decimal :premium_cents, precision: 20, scale: 2, null: false, default: 0
      t.string :currency, limit: 5, null: false
      t.date :trade_date, null: false
      t.date :expiry_date, null: false
      t.string :settlement, limit: 10, null: false, default: "cash"
      t.string :status, limit: 10, null: false, default: "open"
      t.string :hedge_of_type, limit: 40
      t.bigint :hedge_of_id
      t.string :hedge_unit_type, limit: 40
      t.datetime :expiry_reminded_at
      t.json :json_fields
      t.datetime :deleted_at
      t.timestamps

      t.index %i[fund_id status]
      t.index %i[expiry_date status]
      t.index %i[hedge_of_type hedge_of_id]
      t.index :deleted_at
    end

    create_table :derivative_events do |t|
      t.references :derivative_contract, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :event_type, limit: 15, null: false
      t.date :event_date, null: false
      t.decimal :lots, precision: 24, scale: 8
      t.decimal :amount_cents, precision: 20, scale: 2
      t.decimal :value_cents, precision: 20, scale: 2
      t.decimal :delta, precision: 10, scale: 6
      t.string :source, limit: 10, null: false, default: "manual"
      t.string :provider, limit: 40
      t.string :idempotency_key, limit: 64, null: false
      t.references :portfolio_investment, foreign_key: true
      t.references :import_upload, foreign_key: true
      t.text :notes
      t.timestamps

      t.index %i[derivative_contract_id event_date]
      t.index :idempotency_key, unique: true
    end
  end
end
