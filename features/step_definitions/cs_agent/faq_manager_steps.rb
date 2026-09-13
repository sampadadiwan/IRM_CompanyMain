# frozen_string_literal: true

# Step definitions for features/customer_support_agent/faq_manager.feature.
# Access scenarios reuse the request steps in internal_docs_steps.rb; search scenarios reuse
# "the guide search tool is called with keywords" from guide_search_ranking_steps.rb.

Given('a {string} FAQ on guide {string} asking {string} with answer {string}') do |status, guide_key, question, answer|
  entry = FaqEntry.create!(guide_key: guide_key, faq_group: "how_to", question: question, answer: answer)
  entry.publish!(nil) || raise("publish failed: #{entry.errors.full_messages}") if status == "published"
end

Given('a search synonym {string}') do |terms|
  GuideSearchSynonym.create!(terms: terms)
end

Given('the FAQ {string} answer is changed to {string} without validation') do |question, answer|
  FaqEntry.find_by!(question: question).update_columns(answer: answer)
end

When('the FAQ {string} is published') do |question|
  @faq_entry = FaqEntry.find_by!(question: question)
  @faq_entry.publish!(nil)
end

When('a {string} FAQ is saved on guide {string} with audience {string}') do |status, guide_key, audience|
  @faq_entry = FaqEntry.new(guide_key: guide_key, faq_group: "why", question: "Is this public?", answer: "Yes.",
                            status: status, audience: audience)
  @faq_entry.save
end

When('the guide {string} is rendered') do |guide_key|
  renderer = Class.new { include WithGuideRendering }.new
  @rendered_guide = Nokogiri::HTML::DocumentFragment.parse(
    renderer.send(:render_guide_markdown, Rails.root.join("docs/user_guides/#{guide_key}.md"))
  )
end

When('the user requests the FAQ page for {string}') do |question|
  step %(the user requests "/faq_entries/#{FaqEntry.find_by!(question: question).id}")
end

When('the user requests the edit page for the FAQ {string}') do |question|
  step %(the user requests "/faq_entries/#{FaqEntry.find_by!(question: question).id}/edit")
end

When('the FAQ verification job runs') do
  FaqVerificationJob.perform_now
end

When('the FAQs are exported to a spreadsheet') do
  @spreadsheet_path = Rails.root.join("tmp/faq_manager_#{SecureRandom.hex(4)}.xlsx")
  File.binwrite(@spreadsheet_path, FaqSpreadsheet.export(FaqEntry.all))
  sheet = Roo::Spreadsheet.open(@spreadsheet_path.to_s, extension: :xlsx).sheet(0)
  @spreadsheet_rows = (1..sheet.last_row).map { |i| sheet.row(i) }
end

When('the spreadsheet answer for {string} is changed to {string}') do |question, answer|
  headers = @spreadsheet_rows.first
  row = @spreadsheet_rows.find { |r| r[headers.index("Question")] == question }
  row[headers.index("Answer")] = answer
end

When('the spreadsheet gets a new row on guide {string} asking {string} with answer {string}') do |guide_key, question, answer|
  @spreadsheet_rows << [nil, guide_key, "why", nil, question, answer, nil, "signed_in", "draft", nil, nil]
end

When('the spreadsheet is imported') do
  package = Axlsx::Package.new
  package.workbook.add_worksheet(name: "FAQs") { |sheet| @spreadsheet_rows.each { |r| sheet.add_row(r) } }
  File.binwrite(@spreadsheet_path, package.to_stream.read)
  @import_result = FaqSpreadsheet.import(@spreadsheet_path, user: nil)
ensure
  FileUtils.rm_f(@spreadsheet_path)
end

Then('the rendered guide should contain {string}') do |text|
  expect(@rendered_guide.text).to include(text)
end

Then('the rendered guide should not contain {string}') do |text|
  expect(@rendered_guide.text).not_to include(text)
end

Then('the rendered guide should have {int} FAQ accordion item(s)') do |count|
  expect(@rendered_guide.css(".faq details").size).to eq(count)
end

Then('the rendered FAQ item should be anchored to its FAQ id') do
  expect(@rendered_guide.at_css(".faq details")["id"]).to eq("faq-#{@faq_entry.id}")
end

Then('the FAQ {string} should still be a draft') do |question|
  expect(FaqEntry.find_by!(question: question).status).to eq("draft")
end

Then('the FAQ {string} should be a draft') do |question|
  expect(FaqEntry.find_by!(question: question).status).to eq("draft")
end

Then('the FAQ {string} should have the error {string}') do |_question, message|
  expect(@faq_entry.errors.full_messages.join(" ")).to include(message)
end

Then('the FAQ should be invalid with an error on {string}') do |attribute|
  expect(@faq_entry.errors[attribute.to_sym]).to be_present
end

Then('the FAQ {string} should need verification') do |question|
  expect(FaqEntry.find_by!(question: question)).to have_attributes(needs_verification: true)
end

Then('the FAQ {string} should have answer {string}') do |question, answer|
  expect(FaqEntry.find_by!(question: question).answer).to eq(answer)
end

Then('the guide search output should contain {string}') do |text|
  expect(@guide_search_output).to include(text)
end

Then('the guide search should record a hit that is strong') do
  expect(@guide_search_tool.message_attributes).to include(guide_search_hit: true, guide_search_strong_hit: true)
end

Then('the guide search should record a hit that is not strong') do
  expect(@guide_search_tool.message_attributes).to include(guide_search_hit: true, guide_search_strong_hit: false)
end

Then('the import should report {int} created, {int} updated and {int} errors') do |created, updated, errors|
  expect([@import_result.created, @import_result.updated, @import_result.errors.size]).to eq([created, updated, errors]),
                                                                                          @import_result.errors.join("\n")
end
