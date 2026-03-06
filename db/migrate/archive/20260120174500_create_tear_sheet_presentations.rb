class CreateTearSheetPresentations < ActiveRecord::Migration[8.1]
  def change
    create_table :tear_sheet_presentations do |t|
      t.references :portfolio_report_extract, null: false, foreign_key: true, index: { unique: true }
      t.references :entity, null: false, foreign_key: true
      t.string :title
      t.json :blueprint
      t.text :content_html, size: :long

      t.timestamps
    end
  end
end
