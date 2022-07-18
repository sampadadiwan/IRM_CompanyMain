class CreateApprovals < ActiveRecord::Migration[7.0]
  def change
    create_table :approvals do |t|
      t.string :title
      t.references :entity, null: false, foreign_key: true
      t.integer :approved_count, default: 0
      t.integer :rejected_count, default: 0

      t.timestamps
    end
  end
end
