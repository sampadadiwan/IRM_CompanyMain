class AddUserAccessRightsToUserCache < ActiveRecord::Migration[7.1]
  def change
    AccessRight.where.not(user_id: nil).find_each do |access_right|
      access_right.user.cache_access_rights(access_right)
    end
  end
end
