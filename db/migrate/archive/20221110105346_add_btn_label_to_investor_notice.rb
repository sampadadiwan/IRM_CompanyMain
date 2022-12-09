class AddBtnLabelToInvestorNotice < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_notices, :btn_label, :string, limit: 40
  end
end
