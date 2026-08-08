# Steps for features/core/lp_crm.feature — the LP CRM MVP
# (docs/features/lp_relationship_crm_alt_mvp_prd.md).
#
# Relies on shared steps for login ("Im logged in..."), investor setup
# ("there is an existing investor"), and the investor access form
# ("I fill the investor access form with ..." / "I click on ...").

require 'rake'

# Runs the real rake task (lib/tasks/lp_crm_custom_fields.rake) so the seeding
# path itself is covered, not a test-only re-implementation of it.
Given('the LP CRM custom fields are seeded') do
  Rails.application.load_tasks unless Rake::Task.task_defined?('lp_crm:seed_custom_fields')
  # reenable so the task can run again in the same process — the Background runs
  # it once per scenario, and the idempotence scenario runs it twice
  Rake::Task['lp_crm:seed_custom_fields'].reenable
  Rake::Task['lp_crm:seed_custom_fields'].invoke(@entity.id.to_s)
end

Then('the entity should have the LP CRM custom fields configured') do
  ia_form = @entity.form_types.where(name: 'InvestorAccess').last
  inv_form = @entity.form_types.where(name: 'Investor').last
  expect(ia_form).to be_present
  expect(inv_form).to be_present
  # Exactly one field per seed definition — a second seeding run must not duplicate
  expect(ia_form.form_custom_fields.pluck(:name).sort).to eq(%w[designation intro linked_in poc_role primary_contact])
  expect(inv_form.form_custom_fields.where(name: %w[engagement_status relationship_owner]).count).to eq(2)
end

Given('I am at the stakeholder details page') do
  # Lands on the show page with the stakeholder-users (accesses) tab active
  visit(investor_path(@investor))
  sleep(1)
end

# The contact custom fields are rendered by custom_form_fields inside the
# investor access form, as investor_access[properties][<field_name>] inputs.
Given('I fill the contact custom fields with designation {string}, POC role {string} and intro {string}') do |designation, poc_role, intro|
  fill_in('investor_access_properties_designation', with: designation)
  select(poc_role, from: 'investor_access_properties_poc_role')
  fill_in('investor_access_properties_intro', with: intro)
end

Then('the contact {string} should be stored unapproved with designation {string} and POC role {string}') do |email, designation, poc_role|
  contact = InvestorAccess.find_by(email: email)
  expect(contact).to be_present
  # approved=false is what makes this a CRM contact rather than portal access
  expect(contact.approved).to be_falsey
  expect(contact.json_fields['designation']).to eq(designation)
  expect(contact.json_fields['poc_role']).to eq(poc_role)
end

Then('no access email should have been sent to {string}') do |email|
  # Cucumber runs the :inline ActiveJob adapter, so any notification would
  # already sit in ActionMailer::Base.deliveries — an unapproved contact gets none
  recipients = ActionMailer::Base.deliveries.flat_map(&:to)
  expect(recipients).not_to include(email)
end

When('I visit the contact page for {string}') do |email|
  @contact = InvestorAccess.find_by(email: email)
  expect(@contact).to be_present
  visit(investor_access_path(@contact))
  sleep(1)
end

Then('I should see the contact details {string}, {string} and {string}') do |designation, poc_role, intro|
  # Custom fields render as label/value rows inside the details table
  expect(page).to have_content('Designation')
  expect(page).to have_content(designation)
  expect(page).to have_content('POC Role')
  expect(page).to have_content(poc_role)
  expect(page).to have_content(intro)
end

Then('I should see the {string} and {string} tabs but no {string} tab') do |tab1, tab2, hidden_tab|
  within('#investor_access_tabs') do
    expect(page).to have_content(tab1)
    expect(page).to have_content(tab2)
    # Fund Access only renders for investor-advisor users
    expect(page).not_to have_content(hidden_tab)
  end
end

Given('there is a contact {string} named {string} for the investor') do |email, full_name|
  first_name, last_name = full_name.split(' ', 2)
  # Created directly (not via the UI — scenario 2 covers that) to keep this
  # scenario focused on the notes/tasks flow
  InvestorAccess.create!(
    investor: @investor,
    entity: @entity,
    email: email,
    first_name: first_name,
    last_name: last_name,
    approved: false
  )
end

When('I add a note {string} from the contact Notes tab') do |details|
  @note_details = details
  # The Notes tab is active by default; its lazy turbo frame loads the notes
  # list scoped to this contact (owner + touch_point)
  within('#notes-tab') do
    click_on('New Note')
    # The touch point must arrive preselected from the tab's filter params
    expect(page).to have_select('note_touch_point_id', selected: "#{@contact.full_name} (#{@contact.email})")
    find('#note_details').set(details)
    click_on('Save')
  end
  sleep(1)
end

Then('the note {string} should be linked to the contact {string}') do |details, email|
  note = Note.last
  expect(note.details.body.to_plain_text).to include(details)
  # The touch point is the InvestorAccess record, scoping the note to this
  # contact under this stakeholder
  expect(note.touch_point).to eq(InvestorAccess.find_by(email: email))
  expect(note.owner).to eq(@investor)
end

Then('I should see {string} in the notes list') do |name|
  # The "With" column added to the notes table shows the touch point's name
  within('#notes_table_body') do
    expect(page).to have_content(name)
  end
end

When('I add a task {string} from the contact Tasks tab') do |details|
  # Scoped to the contact tab nav — the sidebar also has a "Tasks" link
  within('#investor_access_tabs') { click_on('Tasks') } # tasks lazy frame loads on first display
  within('#tasks-tab') do
    expect(page).to have_content('New Task')
    click_on('New Task')
    expect(page).to have_select('task_touch_point_id', selected: "#{@contact.full_name} (#{@contact.email})")
    find("trix-editor[input='task_details_trix_input_task']").set(details)
    click_on('Save')
  end
  sleep(1)
end

Then('the task {string} should be linked to the contact {string}') do |details, email|
  task = Task.last
  expect(task.details.body.to_plain_text).to include(details)
  expect(task.touch_point).to eq(InvestorAccess.find_by(email: email))
  expect(task.owner).to eq(@investor)
end

Then('the contact tabs should not show the note {string}') do |details|
  # Wait for the lazy notes frame to load before asserting absence, otherwise
  # an unloaded frame would pass vacuously
  within('#notes-tab') do
    expect(page).to have_content('New Note')
    expect(page).not_to have_content(details)
  end
end

When('I set the stakeholder engagement status to {string}') do |status|
  visit(edit_investor_path(@investor))
  # engagement_status is a seeded Select custom field on the Investor form
  select(status, from: 'investor_properties_engagement_status')
  click_on('Save')
  sleep(1)
end

Then('the investor engagement status should be {string}') do |status|
  expect(@investor.reload.json_fields['engagement_status']).to eq(status)
end

# Builds the spreadsheet at runtime (no binary fixture to maintain) with the
# standard columns plus CRM custom-field columns, then drives the same upload UI
# as "Given I upload an investor access file for employees".
When('I upload a stakeholder users file with CRM columns for {string}') do |email|
  path = Rails.root.join('tmp', "lp_crm_contacts_#{Process.pid}.xlsx").to_s
  package = Axlsx::Package.new
  package.workbook.add_worksheet(name: 'Contacts') do |sheet|
    # All STANDARD_HEADERS must be present — the xlsx preview JS disables the
    # Save button when any expected column is missing from the sheet
    sheet.add_row ['Stakeholder', 'First Name', 'Last Name', 'Email', 'Email Enabled', 'Cc',
                   'Country Code', 'Phone', 'WhatsApp Enabled', 'Approved',
                   'Designation', 'POC Role', 'Intro']
    sheet.add_row [@investor.investor_name, 'Imp', 'Orta', email, 'Yes', nil,
                   'IN', '5550001111', 'No', 'No',
                   'COO', 'Finance', 'Met via bulk import']
  end
  package.serialize(path)

  visit(investor_path(@investor))
  find('#stakeholder_users_tab').click
  find('#upload_stakeholder_users').click
  fill_in('import_upload_name', with: 'LP CRM Contacts Upload')
  attach_file('files[]', path, make_visible: true)
  sleep(8) # JS direct-upload to /upload endpoint; same window as the standard upload step
  click_on('Save')
  expect(page).to have_content('Import Upload:', wait: 15)
  # Run the import inline so the assertions below see the result
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('the imported contact {string} should be unapproved with designation {string}, POC role {string} and intro {string}') do |email, designation, poc_role, intro|
  contact = InvestorAccess.find_by(email: email)
  expect(contact).to be_present
  # Approved=No in the sheet → contact-only, no portal access
  expect(contact.approved).to be_falsey
  # Custom columns land in json_fields under the normalized field keys, matching
  # the seeded form fields (so no duplicate FormCustomFields get created)
  expect(contact.json_fields['designation']).to eq(designation)
  expect(contact.json_fields['poc_role']).to eq(poc_role)
  expect(contact.json_fields['intro']).to eq(intro)
  expect(contact.form_type&.name).to eq('InvestorAccess')
end
