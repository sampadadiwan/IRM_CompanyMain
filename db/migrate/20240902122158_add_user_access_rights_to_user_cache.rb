class AddUserAccessRightsToUserCache < ActiveRecord::Migration[7.1]
  def change
    puts "######################################################"
    puts "Please run the AddUserAccessRightsToUserCache maunally"
    puts "######################################################"
    # User.update_all(access_rights_cache: {})
    # AccessRight.all.each do |access_right|
    #   access_right.add_to_user_access_rights_cache
    # end; nil
  end
end
