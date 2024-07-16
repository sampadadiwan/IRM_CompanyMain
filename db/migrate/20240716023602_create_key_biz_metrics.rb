class CreateKeyBizMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :key_biz_metrics do |t|
      t.string :name
      t.string :metric_type
      t.decimal :value, precision: 20, scale: 2, default: 0.0
      t.string :display_value
      t.string :notes
      t.text :query
      t.datetime :run_date
      t.timestamps
    end
  end
end
