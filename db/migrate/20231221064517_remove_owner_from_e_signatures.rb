class RemoveOwnerFromESignatures < ActiveRecord::Migration[7.1]
  def up
    add_reference :e_signatures, :document, foreign_key: true, index: true
    ESignature.all.each do |esign|
      esign.update_column(:document_id, esign.owner_id)
    end
    remove_reference :e_signatures, :owner, polymorphic: true, index: true
  end

  def down
    add_reference :e_signatures, :owner, foreign_key: true, index: true
    ESignature.all.each do |esign|
      esign.update_columns(owner_id: esign.document_id, owner_type: "Document")
    end
    remove_reference :e_signatures, :document, polymorphic: true, index: true
  end
end
