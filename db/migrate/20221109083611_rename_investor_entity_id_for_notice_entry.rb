class RenameInvestorEntityIdForNoticeEntry < ActiveRecord::Migration[7.0]
  def change
    drop_table :investor_notice_entries
    create_table :investor_notice_entries do |t|
      t.references :investor_notice, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.references :investor_entity, null: false, foreign_key: { to_table: :entities }
      t.boolean :active, default: false

      t.timestamps
    end
  end
end
