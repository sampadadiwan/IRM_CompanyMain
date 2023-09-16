class CreateAllocationRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :allocation_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date
      t.boolean :fund_ratios
      t.boolean :generate_soa
      t.string :template_name, limit: 30

      t.timestamps
    end
  end
end
