  Given('given there is a document {string} for the entity') do |arg|
    @document = FactoryBot.build(:document, entity: @entity, user: @entity.employees.sample)
    key_values(@document, arg)
    @document.save!
    puts "\n####Document####\n"
    puts @document.to_json
  end
  
  Given('I should have access to the document') do
    Pundit.policy(@user, @document).show?.should == true
  end

  Given('I should not have access to the document') do
    Pundit.policy(@user, @document).show?.should == true
  end
  
  Then('another user has {string} access to the document') do |arg|
    Pundit.policy(@another_user, @document).show?.to_s.should == arg
  end

  Then('employee investor has {string} access to the document') do |arg|
    Pundit.policy(@employee_investor, @document).show?.to_s.should == arg
  end


Given('investor has access right {string} in the document') do |arg1|
    @access_right = AccessRight.new(owner: @document, entity: @entity)
    key_values(@access_right, arg1)
    puts @access_right.to_json
    
    @access_right.save
    puts "\n####Access Right####\n"
    puts @access_right.to_json  
end
  
Given('I am at the documents page') do
  visit(documents_path)
end

When('I create a new document {string}') do |args|
  Folder.create!(name: "Test Folder", parent: Folder.first, folder_type: :regular, entity_id: Folder.first.entity_id)

  @document = Document.new
  key_values(@document, args)
  @document.tag_list = "capybara,testing"

  click_on("New Document")
  fill_in("document_name", with: @document.name)
  fill_in("document_tag_list", with: @document.tag_list.join(","))
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  check('document_download') if @document.download
  check('document_printing') if @document.printing
  select("Test Folder", from: "document_folder_id") if @document.folder_id


  sleep(2)
  click_on("Save")
  sleep(8)
  
end

Then('an document should be created') do
  @created_doc = Document.last
  puts "\n####Document####\n"
  puts @created_doc.to_json  

  @created_doc.name.should == @document.name
  @created_doc.download.should == @document.download
  @created_doc.printing.should == @document.printing
  @created_doc.tag_list.should == @document.tag_list
  if @document.owner
    @created_doc.entity_id.should == @document.owner.entity_id
  else
    @created_doc.entity_id.should == @user.entity_id
  end
  @document = @created_doc
end

Given('the entity has a folder {string}') do |args|
  @folder = Folder.new(parent: Folder.first, entity: @user.entity)
  key_values(@folder, args)
  @folder.save!
end

Given('the folder has access rights {string}') do |arg1|
  @access_right = AccessRight.new(owner: @folder, entity: @user.entity)
  key_values(@access_right, arg1)
  puts @access_right.to_json
  
  @access_right.save
  puts "\n####Access Right####\n"
  puts @access_right.to_json  
end

Then('the document should have the same access rights as the folder') do
  puts "\n####Document Access Right####\n"
  puts @document.access_rights.to_json  

  @document.access_rights.count.should == @folder.access_rights.count
  @document.access_rights.each_with_index do |dar, idx|
    far = @folder.access_rights[idx]
    far.access_to_investor_id.should == dar.access_to_investor_id
    far.access_to_category.should == dar.access_to_category
    far.entity_id.should == dar.entity_id    
  end
end


Then('I should see the document details on the details page') do
  page.should have_content(@document.name)
  page.should have_content(@document.tag_list)
  page.should have_content(@document.folder.full_path)
end

Then('I should see the document in all documents page') do
  visit(documents_path)
  page.should have_content(@document.name)
  page.should have_content(@document.tag_list)
  page.should have_content(@document.folder.full_path)
end

Then('the deal document details must be setup right') do
  @document.owner.should == @deal
  @document.folder.name.should == @deal.name
  @document.folder.full_path.should == "/Deals/#{@deal.name}"
end

Then('the sale document details must be setup right') do
  @document.owner.should == @sale
  @document.folder.name.should == @sale.name
  @document.folder.full_path.should == "/Secondary Sales/#{@sale.name}"
end

Then('the offer document details must be setup right') do
  @document.owner.should == @offer
  @document.folder.name.should == @offer.user.full_name
  @document.folder.full_path.should == "/Secondary Sales/#{@offer.secondary_sale.name}/Offers/#{@offer.user.full_name}"
end

Then('the interest document details must be setup right') do
  @document.owner.should == @interest
  @document.folder.name.should == @interest.interest_entity.name
  @document.folder.full_path.should == "/Secondary Sales/#{@interest.secondary_sale.name}/Interests/#{@interest.interest_entity.name}"
end



Given('I visit the deal investor details page') do
  @deal_investor = @deal.deal_investors.first
  visit( deal_investor_path(@deal_investor) )
end

When('the deal investor document details must be setup right') do
  @document.owner.should == @deal_investor
  @document.folder.name.should == @deal_investor.investor_name
  @document.folder.full_path.should == "/Deals/#{@deal.name}/Deal Investors/#{@deal_investor.investor_name}"
end


Given('given there is a document {string} for the deal') do |args|
  @document = Document.new(entity: @deal.entity, name: "Test", 
    text: Faker::Company.catch_phrase, user: @user, owner: @deal,
    folder: @deal.entity.folders.sample, file: File.new("public/sample_uploads/Instructions.txt", "r"))

  key_values(@document, args)
  @document.save!  

  puts "\n####Document####\n"
  puts @document.to_json  

end

Given('given there is a document {string} for the sale') do |args|
  @document = Document.new(entity: @sale.entity, name: "Test", 
    text: Faker::Company.catch_phrase, user: @user, owner: @sale,
    folder: @sale.entity.folders.sample, file: File.new("public/sample_uploads/Instructions.txt", "r"))

  key_values(@document, args)
  @document.save!

  puts "\n####Document####\n"
  puts @document.to_json  

end
