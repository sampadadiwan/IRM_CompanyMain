class AddFileDataToOptionPool < ActiveRecord::Migration[7.0]
  def change
    add_column :option_pools, :certificate_signature_data, :text
  end
end
