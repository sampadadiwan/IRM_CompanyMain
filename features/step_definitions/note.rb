When('I create a new note {string}') do |arg1|
  click_on("Show", match: :first)
  click_on("Add Note", match: :first)
  find('#note_details').set(arg1)
  click_on("Save")
end

Then('an note should be created') do
  Note.count.should == 1
end

Then('I should see the note details on the details page') do
  expect(page).to have_content("Hi, How are you?")
end

Then('I should see the note in all notes page') do
  visit("/notes")
  expect(page).to have_content("Hi, How are you?")
end
