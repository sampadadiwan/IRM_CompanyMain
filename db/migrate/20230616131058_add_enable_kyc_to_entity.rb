class AddEnableKycToEntity < ActiveRecord::Migration[7.0]
  def change
    # add_column :entities, :enable_kycs, :boolean, default: false
    Entity.where(enable_funds: true).update_all(enable_kycs: true)
    User.joins(:entity).where("entities.enable_funds": true).each do |employee|
      employee.permissions.set(:enable_kycs)
      employee.save      
    end
  end
end
