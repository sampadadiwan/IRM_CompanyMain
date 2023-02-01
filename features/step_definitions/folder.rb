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