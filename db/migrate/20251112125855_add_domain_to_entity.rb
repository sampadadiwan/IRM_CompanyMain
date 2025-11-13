class AddDomainToEntity < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :domain, :string
  end
end
