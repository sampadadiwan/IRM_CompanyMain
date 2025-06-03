class AddFormTypeToFundRatio < ActiveRecord::Migration[8.0]
  def change
    add_reference :fund_ratios, :form_type, null: true, foreign_key: true
    add_reference :fund_reports, :form_type, null: true, foreign_key: true

  end
end
