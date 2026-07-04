# ── Helpers ───────────────────────────────────────────────────────────────────

# Builds a single-sheet XLSX for DealActivityTemplate imports.
# Options:
#   :missing_columns — emit a bad header row (no "Title"/"Days") to trigger validation failure
def build_deal_activity_template_workbook(row_count, opts = {})
  require "caxlsx"
  tmp = Tempfile.new(["deal_activity_templates_test", ".xlsx"])

  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Deal Activity Templates") do |ws|
      if opts[:missing_columns]
        # Intentionally wrong header — missing the required "Title" and "Days" columns.
        ws.add_row(["Step Name"])
        ws.add_row(["Step One"])
      else
        ws.add_row(["Title*", "Days*"])
        row_count.times do |i|
          ws.add_row(["Imported Step #{i + 1}", (i + 1) * 5])
        end
      end
    end
    p.serialize(tmp.path)
  end

  tmp
end

# Visits the new import-upload form, attaches the file, submits, then runs
# the job synchronously so the test can inspect results immediately.
def run_deal_activity_template_import(tmp_file)
  visit(new_import_upload_path(
    "import_upload[entity_id]":   @user.entity_id,
    "import_upload[import_type]": "DealActivityTemplate",
    "import_upload[owner_type]":  "Deal",
    "import_upload[owner_id]":    @deal.id
  ))
  fill_in("import_upload_name", with: "Test Template Upload")
  attach_file("files[]", tmp_file.path, make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")

  @import_upload = ImportUpload.last
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
ensure
  tmp_file.close
  tmp_file.unlink
end

# Visits the new import-upload form and attaches a file whose header row is
# missing required columns. The xlsx-preview Stimulus controller validates
# headers client-side and disables Save before the form can ever be
# submitted, so this never reaches the server (no ImportUpload is created).
def attempt_deal_activity_template_import_with_missing_columns(tmp_file)
  visit(new_import_upload_path(
    "import_upload[entity_id]":   @user.entity_id,
    "import_upload[import_type]": "DealActivityTemplate",
    "import_upload[owner_type]":  "Deal",
    "import_upload[owner_id]":    @deal.id
  ))
  fill_in("import_upload_name", with: "Test Template Upload")
  attach_file("files[]", tmp_file.path, make_visible: true)

  # Wait for the client-side validation banner to appear before asserting.
  expect(page).to have_css('[data-xlsx-preview-target="status"] .alert-danger',
                            text: /Missing required columns/i)
ensure
  tmp_file.close
  tmp_file.unlink
end

# ── Given steps ───────────────────────────────────────────────────────────────

# Creates a deal with skip_templates: true so no ENV-default activities are
# seeded — giving each scenario full control over the starting template state.
Given('there exists a deal {string} for my company without templates') do |arg1|
  @deal = Deal.new(
    name:           "Series A",
    amount_cents:   500_000,
    status:         "Open",
    currency:       @user.entity.currency,
    entity_id:      @user.entity_id,
    skip_templates: "1"
  )
  key_values(@deal, arg1)
  result = CreateDeal.wtf?(deal: @deal)
  raise "Deal creation failed: #{@deal.errors.full_messages}" unless result.success?
end

Given('the deal has {string} step templates') do |count|
  @pre_existing_template_count = count.to_i
  @pre_existing_template_count.times do |i|
    DealActivity.create!(
      deal:      @deal,
      entity_id: @deal.entity_id,
      title:     "Existing Template #{i + 1}",
      days:      (i + 1) * 2,
      sequence:  i + 1
      # deal_investor_id is nil so set_defaults forces status to "Template"
    )
  end
end

# ── When steps: no-templates ──────────────────────────────────────────────────

When('I create a deal cloning from the source deal with skip_templates') do
  @cloned_deal = Deal.new(
    name:           "Cloned No Templates Deal",
    amount_cents:   100_000_00,
    status:         "Open",
    currency:       @deal.currency,
    entity_id:      @deal.entity_id,
    clone_from_id:  @deal.id,
    skip_templates: "1"
  )
  result = CreateDeal.wtf?(deal: @cloned_deal)
  expect(result.success?).to be true
end

When('I create a deal cloning from the source deal') do
  @cloned_deal = Deal.new(
    name:          "Cloned With Templates Deal",
    amount_cents:  100_000_00,
    status:        "Open",
    currency:      @deal.currency,
    entity_id:     @deal.entity_id,
    clone_from_id: @deal.id
  )
  result = CreateDeal.wtf?(deal: @cloned_deal)
  expect(result.success?).to be true
end

# ── When steps: import templates ──────────────────────────────────────────────

When('I import deal activity templates using an XLSX with {string} rows') do |count|
  @imported_row_count = count.to_i
  # Record what the import should produce so the Then steps can verify.
  @expected_imported_titles = (1..@imported_row_count).map { |i| "Imported Step #{i}" }
  @expected_imported_days   = (1..@imported_row_count).map { |i| i * 5 }
  tmp = build_deal_activity_template_workbook(@imported_row_count)
  run_deal_activity_template_import(tmp)
end

When('I import deal activity templates using an XLSX with missing columns') do
  tmp = build_deal_activity_template_workbook(2, missing_columns: true)
  attempt_deal_activity_template_import_with_missing_columns(tmp)
end

# ── Then steps: no-templates ─────────────────────────────────────────────────

Then('the cloned deal should have {string} step templates') do |count|
  @cloned_deal.reload
  expect(DealActivity.templates(@cloned_deal).count).to eq(count.to_i)
end

# ── Then steps: import templates ──────────────────────────────────────────────

Then('the deal should have {string} activity templates') do |count|
  @deal.reload
  expect(DealActivity.templates(@deal).count).to eq(count.to_i)
end

Then('the imported templates should have the correct titles and days') do
  # Only examine the imported templates (skip any pre-existing ones).
  offset    = @pre_existing_template_count || 0
  templates = DealActivity.templates(@deal).order(:sequence).drop(offset)

  @expected_imported_titles.each_with_index do |title, i|
    expect(templates[i].title).to eq(title)
    expect(templates[i].days).to  eq(@expected_imported_days[i])
  end
end

Then('the imported templates are sequenced after the existing ones') do
  all_templates = DealActivity.templates(@deal).order(:sequence)
  pre_existing  = @pre_existing_template_count || 0

  # Pre-existing templates should occupy the first sequences.
  all_templates.first(pre_existing).each_with_index do |t, i|
    expect(t.sequence).to eq(i + 1)
  end

  # Imported templates must follow in sequence without gaps.
  all_templates.drop(pre_existing).each_with_index do |t, i|
    expect(t.sequence).to be > pre_existing
    expect(t.title).to eq("Imported Step #{i + 1}")
  end
end

Then('the import should fail with a column error') do
  # The Save button is disabled client-side, so the upload is never created
  # server-side and there's no ImportUploadJob to run.
  expect(page).to have_button("Save", disabled: true)
  expect(ImportUpload.count).to eq(0)
end

Then('the deal investor activities should be regenerated to match the imported templates') do
  # Run the regeneration job that the after_commit callback would have queued.
  GenerateDealActivitiesJob.perform_now(@deal.id, "Deal")

  @deal.reload
  template_titles = DealActivity.templates(@deal).pluck(:title)

  @deal.deal_investors.each do |di|
    investor_titles = di.deal_activities.pluck(:title)
    template_titles.each do |title|
      expect(investor_titles).to include(title),
        "Expected deal investor #{di.investor_name} to have activity '#{title}'"
    end
  end
end
