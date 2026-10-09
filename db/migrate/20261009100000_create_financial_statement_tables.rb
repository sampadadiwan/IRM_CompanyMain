# Fund financial statements from account entries: the per-fund mapping (settings, statements,
# accounts, rules, layout), the generated statement sets and the AI mapping drafts.
# New tables only; nothing existing changes.
# See openspec/changes/fund-financial-statements/lld.md#schema-detail
class CreateFinancialStatementTables < ActiveRecord::Migration[8.1]
  def change
    # One row per fund: financial year start and the entries the NAV / capital checks compare against
    create_table :financial_statement_settings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: { unique: true }
      t.integer :fiscal_year_start_month, null: false, default: 1
      t.string :nav_entry_type, limit: 60
      t.string :nav_entry_name, limit: 125
      t.string :capital_entry_type, limit: 60
      t.string :capital_entry_name, limit: 125
      t.timestamps
    end

    # The fund's statements: three core ones (renamable, never deleted) plus any schedules
    create_table :financial_statement_definitions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.string :kind, limit: 20, null: false, default: "schedule"
      t.string :column_style, limit: 12, null: false, default: "for_period"
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[fund_id name], unique: true
    end

    # Typed statement accounts ("Professional fees", expense, movement)
    create_table :financial_statement_accounts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.string :account_type, limit: 12, null: false
      t.string :behaviour, limit: 10, null: false
      t.boolean :flip_sign, null: false, default: false
      t.timestamps
      t.index %i[fund_id name], unique: true
    end

    # (entry type, name) -> account or excluded; name "" means every name of that entry type
    create_table :financial_statement_mapping_rules do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :entry_type, limit: 60, null: false
      t.string :name, limit: 125, null: false, default: ""
      t.references :financial_statement_account, foreign_key: true, index: { name: "idx_on_financial_statement_account_id_fs_mapping_rules" }
      t.boolean :excluded, null: false, default: false
      t.timestamps
      t.index %i[fund_id entry_type name], unique: true, name: "idx_fs_mapping_rules_on_fund_type_name"
    end

    # Ordered rows of each statement: headings, accounts and subtotals
    create_table :financial_statement_layout_rows do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :financial_statement_definition, null: false, foreign_key: true, index: false
      t.integer :position, null: false, default: 0
      t.string :row_type, limit: 10, null: false
      t.string :label, limit: 150
      t.references :financial_statement_account, foreign_key: true, index: { name: "idx_on_financial_statement_account_id_fs_layout_rows" }
      t.json :subtotal_of
      t.timestamps
      t.index %i[financial_statement_definition_id position], name: "idx_fs_layout_rows_on_definition_position"
    end

    # One statement set per fund and period
    create_table :financial_statements do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, limit: 10, null: false, default: "draft"
      t.references :accounting_allocation_run, foreign_key: { to_table: :allocation_runs, on_delete: :nullify }
      t.references :statements_allocation_run, foreign_key: { to_table: :allocation_runs, on_delete: :nullify }
      t.json :checks
      t.integer :unmapped_count, null: false, default: 0
      t.datetime :refreshed_at
      t.json :frozen_data
      t.datetime :locked_at
      t.references :locked_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[fund_id start_date end_date], unique: true, name: "idx_financial_statements_on_fund_period"
    end

    # AI-drafted mappings from an uploaded statement, reviewed before approval
    create_table :financial_statement_mapping_suggestions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :as_at_date, null: false
      t.date :period_start
      # The uploaded statement (Shrine attachment, like Valuation#report)
      t.text :file_data
      t.string :status, limit: 12, null: false, default: "processing"
      t.json :proposal
      t.text :error
      t.timestamps
    end
  end
end
