When('I create a new note {string}') do |arg1|
  @note_details = arg1
  click_on("Show", match: :first)
  # View Notes / Add Note sit in the investor page's Notes menu
  find("#notes_menu").click
  click_on("Add Note", match: :first)
  find('#note_details').set(arg1)
  click_on("Save")
end

Given('there is a note without owner {string}') do |details|
  @note_details = details
  @note = Note.create!(
    details: details,
    entity: @entity,
    user: @user,
    owner: nil,
    owner_type: "Investor",
    on: Date.current
  )
end

Then('an note should be created') do
  Note.count.should == 1
end

Then('I should see the note details on the details page') do
  expect(page).to have_content(@note_details)
end

Then('I should see the note in all notes page') do
  visit("/notes")
  expect(page).to have_content(@note_details)
  expect(page).to have_selector("tr#note_#{@note.id}") if defined?(@note) && @note.present?
end
