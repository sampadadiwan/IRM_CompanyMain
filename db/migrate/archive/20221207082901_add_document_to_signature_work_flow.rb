class AddDocumentToSignatureWorkFlow < ActiveRecord::Migration[7.0]
  def change
    add_reference :signature_workflows, :document, null: true, foreign_key: true
  end
end
