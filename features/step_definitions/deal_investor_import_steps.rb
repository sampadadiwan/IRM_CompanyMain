Given('there is an existing deal investor for the deal') do
  @existing_investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for entity" unless @existing_investor

  @existing_deal_investor = DealInvestor.create!(
    deal:                    @deal,
    investor:                @existing_investor,
    entity_id:               @deal.entity_id,
    status:                  "Active",
    primary_amount_cents:    100_000_00,
    pre_money_valuation_cents: 0,
    tier:                    "Tier 2"
  )

  # Create deal activities for the investor
  DealActivity.templates(@deal).each do |template|
    DealActivity.create!(
      deal:             @deal,
      deal_investor:    @existing_deal_investor,
      entity_id:        @deal.entity_id,
      title:            template.title,
      status:           "incomplete",
      days:             template.days || 0,
      sequence:         template.sequence,
      template_id:      template.id
    )
  end
end

# ─── Given: import deal activity templates ───────────────────────────────────

# Imports specific activity templates for the deal via the DealActivityTemplate
# import mechanism.  Uses the shared helpers from deal_template_management_steps.rb.
Given("the deal has deal activity templates {string} imported") do |titles_csv|
  titles = titles_csv.split(",").map(&:strip)
  tmp = build_deal_activity_template_workbook_for_titles(titles)
  run_deal_activity_template_import(tmp)
  @step_titles = DealActivity.templates(@deal).map(&:title)
  @first_step  = @step_titles.first
end

# Builds a DealActivityTemplate xlsx with the given list of titles (5 days each).
def build_deal_activity_template_workbook_for_titles(titles)
  require "caxlsx"
  tmp = Tempfile.new(["deal_activity_templates_test", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Deal Activity Templates") do |ws|
      ws.add_row(["Title*", "Days*"])
      titles.each_with_index { |title, i| ws.add_row([title, (i + 1) * 5]) }
    end
    p.serialize(tmp.path)
  end
  tmp
end

# ─── xlsx builders ────────────────────────────────────────────────────────────

# Builds a three-sheet workbook matching the new template format.
# Options:
#   :with_steps     — include Deal Steps sheet
#   :with_notes     — include Notes sheet (plain)
#   :with_reminder  — include Notes sheet with reminder columns populated
#   :omit_premoney  — leave Pre Money Valuation blank
#   :custom_fields  — include extra custom-field columns
#   :mixed_dated_notes — Notes sheet with several rows, out of date order and one
#                        undated, to pin down the last_interaction_date recompute
def build_deal_investor_workbook(investor_name, opts = {})
  require "caxlsx"

  investor_headers = [
    "Deal Investor", "Status", "Tags", "Source", "Deal Lead", "Tier",
    "Primary Amount", "Secondary Amount", "Pre Money Valuation"
  ]
  investor_headers += ["Client History", "RM Name"] if opts[:custom_fields]

  pre_money = opts[:omit_premoney] ? "" : "10000000"
  investor_row = [
    investor_name, "Active", "VC", "Referral", "John Doe", "High",
    "1000000", "0", pre_money
  ]
  investor_row += ["Met at event", "Allan"] if opts[:custom_fields]

  tmp = Tempfile.new(["deal_investors_test", ".xlsx"])

  Axlsx::Package.new do |p|
    # Sheet 1 — Deal Investors
    p.workbook.add_worksheet(name: "Deal Investors") do |ws|
      ws.add_row investor_headers
      ws.add_row investor_row
    end

    # Sheet 2 — Deal Steps (optional)
    if opts[:with_steps]
      titles = opts[:step_titles] || ["Deck Sent", "Meeting 1"]
      p.workbook.add_worksheet(name: "Deal Steps") do |ws|
        ws.add_row(["Deal Investor"] + titles)
        ws.add_row([investor_name, "Complete"] + (["Incomplete"] * [titles.length - 1, 0].max))
      end
    end

    # Sheet 3 — Notes (optional)
    if opts[:with_notes] || opts[:with_reminder] || opts[:mixed_dated_notes]
      p.workbook.add_worksheet(name: "Notes") do |ws|
        ws.add_row ["Deal Investor", "On", "Details", "Tags",
                    "Reminder Emails", "Reminder Date"]
        if opts[:with_reminder]
          ws.add_row [investor_name, "2026-01-01", "Met at conference", "Meeting",
                      "investor@example.com", "2026-02-15"]
        elsif opts[:mixed_dated_notes]
          # Deliberately not in date order, and the last row is undated: the recompute
          # must land on the max On (2026-04-15), not on whichever row came last.
          ws.add_row [investor_name, "2026-01-01", "Intro meeting notes", "Meeting", "", ""]
          ws.add_row [investor_name, "2026-04-15", "Diligence call", "Meeting", "", ""]
          ws.add_row [investor_name, "2026-02-20", "Follow up", "Meeting", "", ""]
          ws.add_row [investor_name, "", "Undated thought", "Meeting", "", ""]
        else
          ws.add_row [investor_name, "2026-01-01", "Intro meeting notes", "Meeting", "", ""]
        end
      end
    end

    p.serialize(tmp.path)
  end

  tmp
end

# ─── shared import helper ─────────────────────────────────────────────────────

def run_deal_investor_import(tmp_file)
  visit(new_import_upload_path(
    "import_upload[entity_id]":  @user.entity_id,
    "import_upload[import_type]": "DealInvestor",
    "import_upload[owner_type]": "Deal",
    "import_upload[owner_id]":   @deal.id
  ))
  fill_in("import_upload_name", with: "Test DealInvestor Upload")
  attach_file("files[]", tmp_file.path, make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")

  @import_upload = ImportUpload.last
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload

  if @import_upload.failed_row_count > 0
    puts "Import failed_row_count: #{@import_upload.failed_row_count}"
    puts "Import error_text: #{@import_upload.error_text}"
  end
ensure
  tmp_file.close
  tmp_file.unlink
end

# ─── When steps ───────────────────────────────────────────────────────────────

When("I import deal investors using the new template") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template with deal steps") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  # Templates and @step_titles/@first_step were set by the Given step above.
  raise "No templates — add 'the deal has deal activity templates ... imported' step" if @step_titles.blank?

  tmp = build_deal_investor_workbook(investor.investor_name, with_steps: true, step_titles: @step_titles)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template with notes") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name, with_notes: true)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template with notes on mixed dates") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name, mixed_dated_notes: true)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template with reminder notes") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name, with_reminder: true)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template without pre money valuation") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name, omit_premoney: true)
  run_deal_investor_import(tmp)
end

When("I import deal investors using the new template with custom fields") do
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = build_deal_investor_workbook(investor.investor_name, custom_fields: true)
  run_deal_investor_import(tmp)
end

# ─── Then steps ───────────────────────────────────────────────────────────────

Then("{string} deal investor should be created for the deal") do |count|
  @deal.reload
  expect(@deal.deal_investors.count).to eq(count.to_i)
end

Then("the imported deal investor should have the correct attributes") do
  di = @deal.deal_investors.last
  expect(di.investor_name).to be_present
  expect(di.status).to eq("Active")
  expect(di.primary_amount_cents).to be > 0
end

Then("the deal investor should have deal activities created") do
  di = @deal.deal_investors.last
  expect(di.deal_activities.count).to be > 0
end

When("the step tasks job runs again for the imported deal investor") do
  deal_investor = @deal.deal_investors.last
  first_activity = deal_investor.deal_activities.order(:sequence).first
  GenerateDealStepTasksJob.perform_now(deal_investor.id, @user&.id, first_activity.id)
end

Then("the imported deal investor should have one task each for {string}") do |titles_csv|
  deal_investor = @deal.deal_investors.last
  details = deal_investor.tasks.includes(:rich_text_details).map { |task| task.details.to_plain_text.strip }

  titles_csv.split(",").map(&:strip).each do |title|
    expect(details.count(title)).to eq(1)
  end
end

Then("the imported deal investor should have no task for {string}") do |title|
  deal_investor = @deal.deal_investors.last
  details = deal_investor.tasks.includes(:rich_text_details).map { |task| task.details.to_plain_text.strip }

  expect(details).not_to include(title)
end

Then("the imported deal investor should be on the step {string}") do |step_title|
  deal_investor = @deal.deal_investors.last.reload
  current_step = deal_investor.deal_activities.find_by(template_id: deal_investor.deal_activity_id)

  expect(current_step&.title).to eq(step_title)
end

Then("the deal investor activities should have updated statuses") do
  di = DealInvestor.where(deal_id: @deal.id).last
  # @first_step is the title set in the When step (first template title)
  first_activity = di.deal_activities.find { |a| a.title.casecmp?(@first_step) }
  expect(first_activity).not_to be_nil
  # DealActivity enum returns the key name (capital C for Complete)
  expect(first_activity.status).to eq("Complete")
end

# The importer attaches notes to the DealInvestor (owner), not to the Investor —
# notes.investor_id is left nil, so scoping by it matched nothing.
Then("notes should be created for the deal investor") do
  notes = Note.where(owner: @deal.deal_investors.last)
  expect(notes.count).to be >= 1
  expect(notes.first.details.to_plain_text).to be_present
end

# The recompute runs once at the end of save_data, so it must find the max "On"
# across the whole sheet rather than the last row processed.
Then("the deal investor last interaction date should be {string}") do |date|
  deal_investor = @deal.deal_investors.last

  expect(deal_investor.reload.last_interaction_date).to eq(Date.parse(date))
end

Then("a reminder should be created for the note") do
  note = Note.where(owner: @deal.deal_investors.last).last
  expect(note).not_to be_nil
  expect(note.reminder).not_to be_nil
  expect(note.reminder.email).to eq("investor@example.com")
end

Then("the deal investor pre money valuation should be {string}") do |expected|
  di = @deal.deal_investors.last
  expect(di.pre_money_valuation_cents.to_i).to eq(expected.to_i)
end

Then("the deal investor should have the custom field stored") do
  di = @deal.deal_investors.last
  expect(di.json_fields).to be_present
  # At least one custom field value should be stored
  expect(di.json_fields.values.any?(&:present?)).to be true
end

Then("the import should have {string} failed rows with error {string}") do |count, error_msg|
  expect(@import_upload.failed_row_count).to eq(count.to_i)

  combined = ""
  if @import_upload.import_results.present?
    @import_upload.import_results.open do |io|
      tmp = Tempfile.new(["import_results", ".xlsx"])
      tmp.binmode
      tmp.write(io.read)
      tmp.flush
      data = Roo::Spreadsheet.open(tmp.path)
      all_rows = []
      data.each_with_index do |row, idx|
        next if idx.zero? # skip header row

        all_rows << row.compact.join(" ")
      end
      combined = all_rows.join(" ")
      tmp.close
      tmp.unlink
    end
  end
  puts "Results content: #{combined}"
  expect(combined).to include(error_msg)
end
