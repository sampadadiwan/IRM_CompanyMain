class AddCallBasisToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :call_basis, :string
  end
end
