class AddAllDocsValidToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :all_docs_valid, :boolean, default: false
  end
end
