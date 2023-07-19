class CreateInvestorNoticeItems < ActiveRecord::Migration[7.0]
  def change
    create_table :investor_notice_items do |t|
      t.references :investor_notice, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :title
      t.text :details
      t.string :link
      t.integer :position

      t.timestamps
    end
  end
end
