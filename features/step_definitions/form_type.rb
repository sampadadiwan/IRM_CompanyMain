
Given('the entity has custom fields {string} for {string}') do |args, class_name|
  puts "Creating custom fields for #{class_name} #{args.split('#')}"
  ft = @entity.form_types.create!(name: class_name)
  args.split("#").each do |arg|
    cf = ft.form_custom_fields.build()
    key_values(cf, arg)
    cf.save!
  end
end

Given('there is a FormType {string}') do |args|
  @form_type = FormType.new(entity_id: @entity.id)
  key_values(@form_type, args)
  @form_type.save!
end

Given('Given I upload {string} file for {string} of the entity') do |file_name, ignore|
  @import_file_name = file_name
  visit(form_type_path(@form_type))
  click_on 'Upload Custom Fields'
  fill_in('import_upload_name', with: "FCF Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  sleep 2
  click_on 'Save'

  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('There should be {string} form custom fields created with data in the sheet') do |count|
  file = File.open("./public/sample_uploads/#{@import_file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  form_custom_fields = @form_type.reload.form_custom_fields.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    fcf = form_custom_fields[idx-1]
    ap fcf

    puts "Checking import of #{fcf.name}"
    expect(fcf.name).to eq(user_data['Name']) if user_data['Name'].present?
    expect(fcf.label).to eq(user_data['Label']) if user_data['Label'].present?
    expect(fcf.field_type).to eq(user_data['Field Type'])
    expect(fcf.required.to_s).to eq(user_data['Required'].to_s&.downcase)
    expect(fcf.has_attachment.to_s).to eq(user_data['Has Attachment'].to_s&.downcase)
    expect(fcf.position.to_s).to eq(user_data['Position'].to_s)
    expect(fcf.help_text).to eq(user_data['Help Text'])
    expect(fcf.read_only.to_s).to eq(user_data['Read Only'].to_s&.downcase)
    expect(fcf.show_user_ids).to eq(user_data['Show User IDs'])
    expect(fcf.step).to eq(user_data['Step'])
    expect(fcf.condition_on).to eq(user_data['Condition On'])
    expect(fcf.condition_criteria).to eq(user_data['Condition Criteria'])
    expect(fcf.condition_params).to eq(user_data['Condition Params'])
    expect(fcf.condition_state).to eq(user_data['Condition State'])
    expect(fcf.internal.to_s).to eq(user_data['Internal'].to_s&.downcase)
    expect(fcf.regulatory_field.to_s).to eq(user_data['Regulatory Field'].to_s&.downcase)
    expect(fcf.regulation_type).to eq(user_data['Regulation Type'])
  end
end