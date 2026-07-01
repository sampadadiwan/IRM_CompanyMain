class AddNotifyOnActivationToWorkflowSteps < ActiveRecord::Migration[7.1]
  def change
    add_column :workflow_steps, :notify_on_activation, :boolean, default: true, null: false
  end
end
