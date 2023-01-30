class ChangeTagsToLargerLength < ActiveRecord::Migration[7.0]
  def change
    change_column :investors, :tag_list, :string, null: true, limit: 120
    change_column :investment_opportunities, :tag_list, :string, null: true, limit: 120
    change_column :documents, :tag_list, :string, null: true, limit: 120

    [InvestorKyc, Investor, Fund, CapitalCommitment, CapitalCall, CapitalRemittance, InvestmentOpportunity, ExpressionOfInterest,  Approval, SecondarySale, Interest, Offer, Deal, DealInvestor, DealActivity,  OptionPool, Excercise].each do |cls|
      puts "processing #{cls}"
      cls.all.each do |model|
        if model.documents.present? 
          puts "Updating model.document_folder for #{model}" 
          model.document_folder.full_path = model.folder_path
          model.document_folder.name = model.folder_path.split("/")[-1]
          model.document_folder.save
        end
      end
    end
  end
end
