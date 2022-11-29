class ChangeStateForSignatureWorkflow < ActiveRecord::Migration[7.0]
  def change
    change_column :signature_workflows, :state, :text
  end
end
