class CreateFundReports < ActiveRecord::Migration[7.0]
  def change
    create_table :fund_reports do |t|
      t.references :fund, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :name, limit: 50
      t.date :report_date
      t.string :name_of_scheme
      t.json :data

      t.timestamps
    end
  end
end
