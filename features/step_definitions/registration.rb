

Then('the user should have the roles {string}') do |roles|
  
  puts "\n####User roles####\n"
  puts @user.roles.collect(&:name)
  roles.split(",").each do |role|
    @user.has_cached_role?(role.to_sym).should == true
  end
end
