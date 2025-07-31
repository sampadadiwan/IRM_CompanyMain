class ChangeFormulaNameForAllocateMasterFundAccountEntry < ActiveRecord::Migration[8.0]
  def change
    FundFormula.where(name: "AllocateMasterFundAccountEntry").update_all(name: "AllocateMasterFundAccountEntry-Name")
  end
end
