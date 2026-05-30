class AddStepLabelsToFormTypes < ActiveRecord::Migration[7.2]
  def change
    # Stores step_number => label mappings for extra dynamic steps (e.g. { "4" => "Tax Details", "5" => "FATCA Info" })
    # MySQL uses :json (not :jsonb); no column-level default — model guards with || {}
    add_column :form_types, :step_labels, :json
  end
end
