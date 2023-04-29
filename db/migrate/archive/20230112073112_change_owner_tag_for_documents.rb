class ChangeOwnerTagForDocuments < ActiveRecord::Migration[7.0]
  def change
    change_column :documents, :owner_tag, :string, limit: 40

    Fund.all.each do |f|
      f.documents.where(owner_tag: "Template").update_all(owner_tag: "Commitment Document Template")
    end
  end
end
