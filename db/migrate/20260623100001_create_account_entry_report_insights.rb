class CreateAccountEntryReportInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :account_entry_report_insights do |t|
      t.bigint :entity_id, null: false
      t.bigint :fund_id, null: false
      t.bigint :capital_commitment_id
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :section_key, null: false
      t.string :status
      t.json :content
      t.string :data_fingerprint
      t.datetime :generated_at
      t.bigint :generated_by_id

      t.timestamps
    end

    change_table :account_entry_report_insights, bulk: true do |t|
      t.index :entity_id
      t.index :fund_id
      t.index :capital_commitment_id
      # Not unique: MySQL doesn't enforce uniqueness across rows where capital_commitment_id
      # is NULL (fund-level scope), so de-duping is handled in the job via find_or_initialize_by.
      t.index %i[fund_id capital_commitment_id start_date end_date section_key], name: "idx_ae_report_insights_scope"
    end
  end
end
