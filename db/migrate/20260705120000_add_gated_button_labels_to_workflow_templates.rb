class AddGatedButtonLabelsToWorkflowTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :workflow_templates, :gated_button_labels, :string
  end
end
