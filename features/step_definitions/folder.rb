Then('the folder should have no owner') do
  @folder.owner.should == nil
end

Then('the folder should have no access_rights') do
  @folder.access_rights.should == []
end

Then('the deal document folder should be created') do
  @deal.document_folder.should_not == nil
  @deal.document_folder_id.should == @deal.document_folder.id
  @deal.document_folder.owner.should == @deal
end

Then('the deal data room should be created') do
  @data_room = @deal.data_room_folder
  @data_room.should_not == nil
  @data_room.owner.should == @deal
  @data_room.name.should == "Overview"
  @data_room.full_path.should == "/Deals/#{@deal.name}/Overview"
end

Then('the deal data room should have the correct access_rights') do
  @deal.reload
  @data_room.reload
  puts "\n####data_room.access_rights####\n"
  puts @data_room.access_rights.to_json
  @deal.access_rights.length.should == @data_room.access_rights.length
end

Given('there is a child folder in the data room') do
  @child_folder = Folder.create(name: "Child Folder", parent: @data_room, entity: @data_room.entity)
end

Then('the child folder should have the correct access_rights') do
  @child_folder.owner.should == @data_room.owner
  puts "\n####child_folder.access_rights####\n"
  puts @child_folder.access_rights.to_json
  @child_folder.access_rights.length.should == @data_room.access_rights.length
end

Given('the folder has children {string}') do |string|
  child_folders = string.split("/")
  child_folders.each do |name|
    child = @folder.children.create(name:, entity: @folder.entity)
  end
end

Given('folder {string} has sub-folders {string}') do |parent_folder_name, sub_folders_string|
  parent_folder = Folder.find_by(name: parent_folder_name, entity: @folder.entity)
  sub_folders = sub_folders_string.split("/")
  sub_folders.each do |sub_folder_name|
    parent_folder.children.create!(name: sub_folder_name, entity: @folder.entity)
  end
end

Given('each folder has {string} documents') do |count|
  @folder.reload.descendants.each do |folder|
    count.to_i.times do |i|
      Document.create!(entity: @folder.entity, name: "Doc #{folder.name} #{i}", text: Faker::Company.catch_phrase, user: @user, folder:, file: File.new("public/sample_uploads/GrantLetter.docx", "r"))
    end
  end
end

Given('there is an independent access_right for another user on folder {string}') do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @folder.entity)
  other_user = FactoryBot.create(:user)
  @independent_ar = AccessRight.create!(owner: folder, user_id: other_user.id, cascade: false, entity_id: folder.entity_id)
end

When('the root folder is given access rights') do
  @root_folder_ar = AccessRight.create!(owner: @folder, user_id: @user.id, cascade: true, entity_id: @folder.entity_id)
end

Then('the child folders should have the same access rights') do
  @folder.reload.descendants.each do |folder|
    puts "Checking folder #{folder.name} access rights"
    ar = folder.access_rights.find_by(user_id: @user.id)
    ar.should_not be_nil
    ar.cascade.should == true
    ar.entity_id.should == @folder.entity_id
    ar.parent_access_right_id.should == @root_folder_ar.id
  end
end

Then('the documents should have the same access rights') do
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    puts "Checking document #{doc.name} access rights"
    ar = doc.access_rights.find_by(user_id: @user.id)
    ar.should_not be_nil
    ar.entity_id.should == @folder.entity_id
    ar.parent_access_right_id.should == @root_folder_ar.id
  end
end

Then('the user should have the access_rights in their cache') do
  @user.reload
  # Note: Folder access rights are NOT cached (see AccessRight model line 182 and 202)
  # But Document access rights ARE cached.
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    # Structure: {entity_id: {owner_type: {owner_id: "permissions, metadata"}}}
    @user.access_rights_cache[@user.entity_id]["Document"][doc.id].should_not be_nil
  end
end

Then('folder {string} should still have the independent access_right') do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @folder.entity)
  folder.access_rights.where(id: @independent_ar.id).should be_present
end

When('the root folder access right is deleted') do
  @folder.access_rights.destroy_all
end

Then('the child folders access_rights should be deleted') do
  @folder.reload.descendants.each do |folder|
    puts "Checking post delete folder #{folder.name} access rights"
    folder.access_rights.where(user_id: @user.id).length.should == 0
  end
end

Then('the documents access_rights should be deleted') do
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    puts "Checking post delete document #{doc.name} access rights"
    doc.access_rights.where(user_id: @user.id).length.should == 0
  end

  # Ensure that when the parent is deleted, no access rights remain with parent_id set
  AccessRight.where(parent_access_right_id: @root_folder_ar.id).length.should == 0
end

Then('the user should have no cascading access_rights in their cache') do
  @user.reload
  # Documents should be removed from cache
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    # If the hash or the ID is missing, it's considered deleted from cache
    next if @user.access_rights_cache.dig(@user.entity_id, "Document").nil?
    @user.access_rights_cache[@user.entity_id]["Document"][doc.id].should be_nil
  end
end

Then("I update the folder's name") do
  folder_to_update = Folder.find_by_name("B")
  visit edit_folder_path(folder_to_update)
  #sleep(0.2)
  # field should be disabled
  expect(page).to have_field('folder_name', disabled: true)
  expect(page).to have_field('folder_parent_id', disabled: true)
  #sleep(2)
end

Then('I children folder path should be updated') do
  folder = Folder.find_by_name("B - Updated")
  folder.descendants.each do |descendant|
    expect(descendant.full_path).to include(folder.full_path)
  end
end

Then('an document folder should be present') do
  expect(@deal.document_folder).to(be_present)
end

Then('I edit the name of the deal') do
  visit edit_deal_path(@deal)
  #sleep(0.2)
  fill_in 'deal_name', with: 'Series B'
  click_on 'Save'
  expect(page).to have_content("successfull")
  #sleep(0.1)
end

Then('Path of folder and children should change') do
  expect(@deal.reload.document_folder.full_path).to(eq("/Deals/#{@deal.name}"))
  expect(@deal.document_folder.children.first.full_path).to(eq("/Deals/#{@deal.name}/Overview"))
end

Then('I mock the folder path to be wrong') do
  @deal.document_folder.update_columns(name: "Wrong name")
  @deal.document_folder.update_columns(full_path: "Wrong path")
end

Then('UpdateDocumentFolderPathJob job is triggered') do
  UpdateDocumentFolderPathJob.perform_now(@deal.class.name, @deal.id)
end
