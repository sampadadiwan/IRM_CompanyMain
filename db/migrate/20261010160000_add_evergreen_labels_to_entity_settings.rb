# Per-entity overrides of the evergreen wording (EvergreenLabels): only the words an entity changes,
# e.g. {"unit" => "share", "capital_commitment" => "Account"}; everything else comes from the locale.
class AddEvergreenLabelsToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :evergreen_labels, :json
  end
end
