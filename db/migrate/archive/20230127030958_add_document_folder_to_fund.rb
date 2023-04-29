class AddDocumentFolderToFund < ActiveRecord::Migration[7.0]
  def change
    add_reference :investor_kycs, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :investors, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :capital_calls, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :capital_commitments, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :funds, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :expression_of_interests, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :investment_opportunities, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :approvals, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :interests, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :offers, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :secondary_sales, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :deals, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :deal_activities, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :deal_investors, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :excercises, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :option_pools, :document_folder, null: true, foreign_key: {to_table: :folders}    
  end
end
