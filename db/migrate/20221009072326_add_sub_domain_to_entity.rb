class AddSubDomainToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :sub_domain, :string, limit: 25
    add_index :entities, :sub_domain, unique: true
  end
end
