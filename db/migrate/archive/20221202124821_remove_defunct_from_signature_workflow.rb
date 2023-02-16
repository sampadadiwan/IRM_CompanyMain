class RemoveDefunctFromSignatureWorkflow < ActiveRecord::Migration[7.0]
  def change
    remove_columns :signature_workflows, :signatory_ids
    remove_columns :signature_workflows, :completed_ids
    remove_columns :signature_workflows, :reason    
  end
end
