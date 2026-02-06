
Given('Given I upload a {string} file for {string}') do |file, type|
  @import_file = file
  # Set the owner to Entity for general task imports in this test context
  # Rails requires the param name to match the model attribute name: owner_type, owner_id
  visit(new_import_upload_path("import_upload[entity_id]": @user.entity_id, "import_upload[import_type]": type, "import_upload[owner_type]": "Entity", "import_upload[owner_id]": @user.entity_id))
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  iu = ImportUpload.last
  # Download results to see errors if any
  ImportUploadJob.perform_now(iu.id)
  iu.reload
  if iu.failed_row_count > 0
    puts "IU failed_row_count: #{iu.failed_row_count}"
    puts "IU error_text: #{iu.error_text}"
    # Read the results file to see row errors
    results = iu.import_results.download
    data = Roo::Spreadsheet.open(results.path)
    data.each_with_index do |row, idx|
       puts "Row #{idx}: #{row.inspect}"
    end
  end
  iu.failed_row_count.should == 0
  iu.status.should == "Completed"
end

Then('There should be {string} tasks created with data in {string}') do |count, file_name|
  # Filtering tasks that are not from recurrence rules to avoid confusion in simple tests
  # or just count all if that's expected.
  puts "Tasks count: #{Task.count}"
  puts "Tasks: #{Task.all.pluck(:id, :details, :import_upload_id).inspect}"
  Task.where(task_recurrence_rule_id: nil).count.should == count.to_i
end

Then('There should be {string} task recurrence rules created with data in {string}') do |count, file_name|
  TaskRecurrenceRule.count.should == count.to_i
end
