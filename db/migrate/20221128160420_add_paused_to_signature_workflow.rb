class AddPausedToSignatureWorkflow < ActiveRecord::Migration[7.0]
  def change
    add_column :signature_workflows, :paused, :boolean, default: false
  end
end
