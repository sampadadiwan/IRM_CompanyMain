When('I create a new note {string}') do |arg1|
  @note_details = arg1
  click_on("Show", match: :first)
  # Notes live under the Activity tab; its list's New Note opens the form inline
  within('#investor_tabs') do
    click_on(I18n.t('investor_details_nav.activity'))
    find("a[href='#notes-tab']").click
  end
  within('#notes-tab') { click_on("New Note") }
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
