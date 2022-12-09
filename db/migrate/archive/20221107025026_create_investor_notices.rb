class CreateInvestorNotices < ActiveRecord::Migration[7.0]
  def change
    create_table :investor_notices do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :owner, null: true, polymorphic: true, index: true
      t.date :start_date
      t.text :title
      t.string :link
      t.string :access_rights_metadata
      t.date :end_date
      t.boolean :active, default: false

      t.timestamps
    end
  end
end
