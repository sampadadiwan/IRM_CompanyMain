class AddAllDocsCompletedToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :docs_completed, :boolean, default: false
  end
end
