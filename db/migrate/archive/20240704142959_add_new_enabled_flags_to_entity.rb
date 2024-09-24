class AddNewEnabledFlagsToEntity < ActiveRecord::Migration[7.1]
  def change

    Entity.permissions.set_all!(:enable_import_uploads)
    Entity.permissions.set_all!(:enable_investor_advisors)
    Entity.permissions.set_all!(:enable_form_types)

    User.permissions.set_all!(:enable_import_uploads)
    User.permissions.set_all!(:enable_investor_advisors)
    User.permissions.set_all!(:enable_form_types)

  end
end
