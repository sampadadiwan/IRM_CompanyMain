Given('There is a folder {string} for the KYC') do |folder_name|
  @kyc ||= InvestorKyc.last
  @folder = Folder.find_or_create_by(name: folder_name, entity_id: @kyc.entity_id, owner: @kyc)
  expect(@folder).to be_present
end

Given('there is a template {string} in folder {string}') do |template_name, folder_name|
  @template_name = template_name
  @folder ||= Folder.find_by(name: folder_name, owner: @kyc)
  visit(folder_path(@folder))
  sleep(2)
  click_on("Actions")
  sleep(0.5)
  click_on("New Document")
  #sleep(2)
  fill_in('document_name', with: template_name)

  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{template_name}.docx"), make_visible: true)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  sleep(5)
  check("document_template")
  click_on("Save")
  expect(page).to have_content("successfully")
  @template = Document.where(name: template_name).last
  @template.folder_id = @folder.id
  @template.save
  @template.reload
end

Given('I fill in the kyc doc gen details') do
  @kyc ||= InvestorKyc.last
  type = @kyc.individual? ? "individual" : "non_individual"
  @start_date = Time.zone.parse("01/01/2025")
  @end_date = Time.zone.parse("31/12/2025")
  fill_in("#{type}_kyc_start_date", with: @start_date)
  fill_in("#{type}_kyc_end_date", with: @end_date)
  select(@template_name, from: "#{type}_kyc_template_name")
  sleep(2)
end

Then('the document should be successfully generated for the KYC') do
  @kyc ||= InvestorKyc.last

  name = if @template.tag_list&.downcase =~ /\b#{Regexp.escape('soa')}\b/
    "#{@template_name} #{@start_date.strftime("%d %B,%Y")} to #{@end_date.strftime("%d %B,%Y")} - #{@kyc.to_s}"
  else
     "#{@template_name} - #{@kyc.to_s}"
  end
  @kyc.documents.where(name: name).count.should == 1
end
