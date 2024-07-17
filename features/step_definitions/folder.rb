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
    @data_room.name.should == "Data Room"
    @data_room.full_path.should == "/Deals/#{@deal.name}/Data Room"
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

Given('each folder has a document') do
  @folder.reload.descendants.each do |folder|
    Document.create!(entity: @folder.entity, name: "Doc #{folder.name}", text: Faker::Company.catch_phrase, user: @user, folder:, file: File.new("public/sample_uploads/GrantLetter.docx", "r"))
  end
end

When('the root folder is given access rights') do
  AccessRight.create!(owner: @folder, user_id: @user.id, cascade: true, entity_id: @folder.entity_id)
end

Then('the child folders should have the same access rights') do
  @folder.reload.descendants.each do |folder|
    puts "Checking folder #{folder.name} access rights #{folder.access_rights.first}"
    folder.access_rights.length.should == 1
    folder.access_rights.first.user_id.should == @user.id
    folder.access_rights.first.cascade.should == true    
    folder.access_rights.first.entity_id.should == @folder.entity_id
  end
end

Then('the documents should have the same access rights') do
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    puts "Checking document #{doc.name} access rights #{doc.access_rights.first}"
    doc.access_rights.length.should == 1
    doc.access_rights.first.user_id.should == @user.id    
    doc.access_rights.first.entity_id.should == @folder.entity_id  
  end
end

When('the root folder access right is deleted') do
  @folder.access_rights.destroy_all
end

Then('the child folders access_rights should be deleted') do
  @folder.reload.descendants.each do |folder|
    puts "Checking post delete folder #{folder.name} access rights #{folder.access_rights.first}"
    folder.access_rights.length.should == 0
  end
end

Then('the documents access_rights should be deleted') do
  Document.where(folder_id: @folder.reload.descendant_ids).each do |doc|
    puts "Checking post delete document #{doc.name} access rights #{doc.access_rights.first}"
    doc.access_rights.length.should == 0
  end
end