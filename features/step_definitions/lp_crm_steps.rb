# Steps for features/core/lp_crm.feature — the LP CRM MVP
# (docs/modules/investors/lp_relationship_crm_alt_mvp_prd.md).
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

# The touch point is shown on both show pages as a "With" row, linking to the
# contact's page with the matching tab open.
Then('the note and task show pages should link {string} back to the contact') do |full_name|
  visit(note_path(Note.last))
  expect(page).to have_link(full_name, href: investor_access_path(@contact, tab: 'notes-tab'))

  visit(task_path(Task.last))
  expect(page).to have_link(full_name, href: investor_access_path(@contact, tab: 'tasks-tab'))
end

When('I add a note {string} from the contact Notes tab without a touch point') do |details|
  within('#notes-tab') do
    click_on('New Note')
    # Clear the preselected contact — the blank option, selected by value so it
    # works regardless of the option's label
    find("#note_touch_point_id option[value='']").select_option
    find('#note_details').set(details)
    click_on('Save')
  end
  sleep(1)
end

Then('the note {string} should have no touch point') do |details|
  note = Note.all.find { |n| n.details.body.to_plain_text.include?(details) }
  expect(note).to be_present
  expect(note.touch_point_id).to be_nil
end

Then('the contact tabs should not show the note {string}') do |details|
  # Wait for the lazy notes frame to load before asserting absence, otherwise
  # an unloaded frame would pass vacuously
  within('#notes-tab') do
    expect(page).to have_content('New Note')
    expect(page).not_to have_content(details)
  end
end

# ── Deal-side touch points ────────────────────────────────────────────────────
# A DealInvestor's touch points are its parent LP's contacts (DealInvestor
# #touch_point_options), so deal notes/tasks name the same people as stakeholder
# ones and land in that contact's history.

Given('the investor is in an open deal') do
  @deal = FactoryBot.create(:deal, entity: @entity, status: "Open",
                                   name: "LP CRM Deal #{SecureRandom.hex(4)}",
                                   amount_cents: 10_000_000_00, currency: "USD")
  @deal_investor = FactoryBot.create(:deal_investor,
                                     deal: @deal,
                                     investor: @investor,
                                     entity: @entity,
                                     status: "Active",
                                     primary_amount_cents: 5_000_000_00,
                                     pre_money_valuation_cents: 50_000_000_00)
end

Given('there is a contact {string} named {string} for a different stakeholder') do |email, full_name|
  # A second LP under the same GP — its contacts must never be selectable as a
  # touch point on the first LP's deal
  other_entity = FactoryBot.create(:entity, entity_type: "Investor")
  other_investor = FactoryBot.create(:investor, entity: @entity, investor_entity: other_entity,
                                                investor_name: "Other LP #{SecureRandom.hex(3)}")
  first_name, last_name = full_name.split(' ', 2)
  @other_contact = InvestorAccess.create!(
    investor: other_investor,
    entity: @entity,
    email: email,
    first_name: first_name,
    last_name: last_name,
    approved: false
  )
end

# Visits the note form with the same params the deal investor tab's "New Note"
# link sends, rather than driving the deal sidepanel — this scenario is about the
# touch point, not the deal UI.
When('I add a note {string} against the deal investor with touch point {string}') do |details, email|
  contact = InvestorAccess.find_by!(email: email)
  visit(new_note_path('note[owner_id]': @deal_investor.id, 'note[owner_type]': "DealInvestor",
                      'note[entity_id]': @entity.id, embedded_note_context: "deal_investor_tab"))
  select("#{contact.full_name} (#{contact.email})", from: 'note_touch_point_id')
  find('#note_details').set(details)
  click_on('Save')
  sleep(1)
end

When('I add a task {string} against the deal investor with touch point {string}') do |details, email|
  contact = InvestorAccess.find_by!(email: email)
  visit(new_task_path('task[owner_id]': @deal_investor.id, 'task[owner_type]': "DealInvestor",
                      embedded_task_context: "deal_investor_tab"))
  select("#{contact.full_name} (#{contact.email})", from: 'task_touch_point_id')
  find("trix-editor[input='task_details_trix_input_task']").set(details)
  click_on('Save')
  sleep(1)
end

Then('the note {string} should be linked to the contact {string} and owned by the deal investor') do |details, email|
  note = Note.last
  expect(note.details.body.to_plain_text).to include(details)
  expect(note.touch_point).to eq(InvestorAccess.find_by(email: email))
  # The owner stays the deal investor — the touch point is a filter dimension only
  expect(note.owner).to eq(@deal_investor)
end

Then('the task {string} should be linked to the contact {string} and owned by the deal investor') do |details, email|
  task = Task.last
  expect(task.details.body.to_plain_text).to include(details)
  expect(task.touch_point).to eq(InvestorAccess.find_by(email: email))
  expect(task.owner).to eq(@deal_investor)
end

Then('the contact Notes tab should show the deal note {string}') do |details|
  # The tab asks for "everything with this person" (touch_point_scope=all), so a
  # note owned by the deal investor appears alongside the stakeholder's own notes
  within('#notes-tab') do
    expect(page).to have_content(details)
    # The "For" column links to the record the note was logged against
    expect(page).to have_link(href: %r{/deal_investors/})
  end
end

Then('the contact Tasks tab should show the deal task {string}') do |details|
  within('#investor_access_tabs') { click_on('Tasks') } # tasks lazy frame loads on first display
  within('#tasks-tab') do
    expect(page).to have_content(details)
  end
end

Then('the deal investor note form should not offer the contact {string}') do |email|
  visit(new_note_path('note[owner_id]': @deal_investor.id, 'note[owner_type]': "DealInvestor",
                      'note[entity_id]': @entity.id, embedded_note_context: "deal_investor_tab"))
  # The dropdown renders (this LP has its own contact) but lists only this LP's people
  expect(page).to have_select('note_touch_point_id')
  expect(page).not_to have_css("#note_touch_point_id option", text: email)
end

Then('a note on the deal investor with touch point {string} should be rejected') do |email|
  # Params are not to be trusted: the model guard must reject a contact that
  # belongs to some other stakeholder even if the dropdown never offered it
  contact = InvestorAccess.find_by!(email: email)
  note = Note.new(entity: @entity, user: @user, owner: @deal_investor,
                  touch_point: contact, details: "Should not save")
  expect(note).not_to be_valid
  expect(note.errors[:touch_point_id]).to include("is not a contact of this stakeholder")
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
