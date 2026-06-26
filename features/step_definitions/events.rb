Given('I create an event for deal') do
	find('a[aria-label="Add an event"]').click
  #sleep(0.5)
	within('td.bg-skyblue') do
    find('a', visible: false).click
  end
  #sleep(1)
end

Given("I add an event for today's date") do
	today = Date.today
  fill_in "Title", with: "Sample Event"
  fill_in "Description", with: "This is a sample event."
  click_button "Save"
  #sleep(1)
end

Given("I click on the Sample Event and validate the event creation") do
  expect(page).to have_content("Event was successfully created.")
  expect(page).to have_content("Sample Event")
  expect(page).to have_content("This is a sample event.")
  expect(page).to have_content(I18n.l(Time.zone.now.midnight, format: :long_date_time))
  expect(Event.count).to(eq(1))
end
