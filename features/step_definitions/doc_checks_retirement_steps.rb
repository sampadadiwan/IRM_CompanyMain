# Steps for the Doc Questions retirement (deploy 2) — features/core/doc_checks_retirement.feature.
# Worked examples R1–R5 in openspec/changes/document-checks/design.md#worked-examples

require Rails.root.join("db/migrate/20261005090000_retire_doc_questions.rb")

# Whether the app routes a request at all (the test environment raises instead of rendering a 404)
def routed?(path, method: :get)
  Rails.application.routes.recognize_path(path, method:)
  true
rescue ActionController::RoutingError
  false
end

# ── R1 ──
Then("the page {string} should not be found") do |path|
  expect(routed?(path)).to be(false)
end

Then("the KYC list's Document checks menu should link to {string}") do |path|
  visit investor_kycs_path
  expect(page).to have_css("a[href='#{path}']", visible: :all)
end

# ── R2 ──
Then("{string} should not be an import type") do |type|
  expect(ImportUpload::TYPES).not_to include(type)
  expect(ImportUpload::SAMPLES.keys.grep(/DOC_QUESTION/)).to be_empty
end

# A record from before the retirement: its type is no longer offered, but it still opens
Then("an earlier {string} import upload should still open") do |type|
  upload = ImportUpload.new(entity: @entity, owner: @entity, import_type: type, name: "Earlier #{type} upload",
                            user: @user, status: "Completed", total_rows_count: 3, processed_row_count: 3,
                            import_file: Rails.public_path.join("sample_uploads/doc_checks.xlsx").open)
  upload.save!(validate: false)
  visit import_upload_path(upload)
  expect(page).to have_content("Earlier #{type} upload")
end

# ── R3 ──
Then("posting to the KYC's old {string} action should not be found") do |action|
  expect(routed?("/investor_kycs/#{@investor_kyc.id}/#{action}", method: :post)).to be(false)
end

Then("the KYC page's Check documents button should post to Document Checks") do
  visit investor_kyc_path(@investor_kyc)
  form = find("#investor_kyc_validate_docs_with_ai_btn", visible: :all).ancestor("form", visible: :all)
  expect(form[:action]).to include("/doc_check_runs")
end

# ── R4 ──
Then("the database should have no table {string}") do |table|
  expect(ActiveRecord::Base.connection.table_exists?(table)).to be(false)
end

Then("the {string} table should have no column {string}") do |table, column|
  expect(ActiveRecord::Base.connection.column_exists?(table, column)).to be(false)
end

Then("the {string} table should still have the column {string}") do |table, column|
  expect(ActiveRecord::Base.connection.column_exists?(table, column)).to be(true)
end

# ── R5 ── the legacy tables as an environment that hasn't converted still has them (the test schema is
# already past the drop); the migration then runs against them for real
Given("an environment still has {int} Doc Questions, {int} of them converted") do |total, converted|
  connection = ActiveRecord::Base.connection
  connection.create_table(:doc_questions) do |t|
    t.bigint :entity_id
    t.text :question
  end
  connection.create_table(:doc_check_conversion_logs) do |t|
    t.bigint :doc_question_id
    t.string :reason
  end
  @legacy_question_ids = Array.new(total) do |i|
    connection.insert("INSERT INTO doc_questions (entity_id, question) VALUES (#{@entity.id}, 'Question #{i + 1}?')")
  end
  @legacy_question_ids.first(converted).each do |id|
    DocCheck.create!(entity: @entity, document_name: "CML", action: "question", look_for: "Converted #{id}?",
                     legacy_doc_question_id: id)
  end
end

When("the retirement migration runs") do
  @retirement_error = nil
  RetireDocQuestions.new.exec_migration(ActiveRecord::Base.connection, :up)
rescue StandardError => e
  @retirement_error = e
end

Then("it should stop with {string}") do |message|
  expect(@retirement_error&.message.to_s.squish).to eq(message)
end

Then("the Doc Questions table should still be there") do
  expect(ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM doc_questions").to_i).to eq(@legacy_question_ids.size)
end

When("the other Doc Question is converted and the retirement migration runs") do
  converted = DocCheck.where(entity: @entity).where.not(legacy_doc_question_id: nil).pluck(:legacy_doc_question_id)
  (@legacy_question_ids - converted).each do |id|
    DocCheck.create!(entity: @entity, document_name: "CML", action: "question", look_for: "Converted #{id}?",
                     legacy_doc_question_id: id)
  end
  step "the retirement migration runs"
  expect(@retirement_error).to be_nil
end

# Leave the test schema as it was if a scenario stopped half-way
After("@doc_checks") do
  connection = ActiveRecord::Base.connection
  %i[doc_check_conversion_logs doc_questions].each { |t| connection.drop_table(t, if_exists: true) }
end
