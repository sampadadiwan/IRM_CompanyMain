class AddIuToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :import_upload_id, :integer
  end
end
