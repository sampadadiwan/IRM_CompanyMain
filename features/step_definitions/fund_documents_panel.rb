# Steps for features/core/fund_documents_panel.feature - the fund page Documents panel:
# the LP "Latest Documents" list and the name/tag search box
# (DocumentsController#folder + Document.name_or_tags_matching).

module FundDocumentsPanelHelpers
  # Rows of the right-hand documents list (the turbo frame the search box submits into)
  DOC_ROWS = "#documents_frame tr[id^='document_']".freeze

  # Walks/creates "Reports/Quarterly/2026" below the fund's document folder and returns the leaf
  def fund_subfolder(fund, path)
    path.to_s.split("/").map(&:strip).compact_blank.reduce(fund.document_folder) do |parent, name|
      parent.children.find_or_create_by!(name:, entity_id: fund.entity_id)
    end
  end

  # Creates a document in the fund's folder tree. Documents are created one at a time, so a later
  # call gets a higher id - the LP latest list orders by id desc, i.e. newest first.
  def create_fund_document(fund, name:, folder_path:, tags: nil)
    folder = fund_subfolder(fund, folder_path)
    Document.create!(name:, folder:, entity_id: fund.entity_id, tag_list: tags.presence,
                     user: fund.entity.employees.first,
                     file: File.new("public/img/whatsappQR.png", "r"))
  end

  # The same kind of right the access-rights screen creates for one investor on one document
  def share_document_with_investor(document, investor)
    AccessRight.create!(owner: document, entity_id: document.entity_id, access_type: "Document",
                        access_to_investor_id: investor.id, metadata: "All")
  end

  # Names in the right-hand list, top to bottom (the first link in a row is the document name)
  def documents_panel_names
    all(DOC_ROWS).map { |row| row.first("td.text-col a").text.strip }
  end

  def split_names(csv)
    csv.to_s.split(",").map(&:strip).compact_blank
  end
end
World(FundDocumentsPanelHelpers)

Given('the fund has these documents shared with the investor:') do |table|
  # One document per row, created in row order so the last row is the newest
  table.hashes.each do |row|
    doc = create_fund_document(@fund, name: row["name"], folder_path: row["folder"], tags: row["tags"])
    share_document_with_investor(doc, @investor)
    # Guard: the LP really can see it, or the "is listed" assertions would prove nothing
    expect(Document.for_investor(@investor_user, @fund.entity_id).exists?(id: doc.id)).to be(true)
  end
end

Given('the fund has a document {string} in folder {string} not shared with the investor') do |name, folder_path|
  doc = create_fund_document(@fund, name:, folder_path:)
  # A new document copies its folder's access rights (Document#setup_access_rights, run inline in
  # tests); drop them so this LP has no way to see it
  doc.access_rights.destroy_all
  # Guard: the LP really cannot see it, or the "is left out" assertions would prove nothing
  expect(Document.for_investor(@investor_user, @fund.entity_id).exists?(id: doc.id)).to be(false)
end

Given('another fund {string} has a document {string} shared with the investor') do |fund_name, doc_name|
  # Same GP entity and same LP, but a different fund - so a different folder tree
  other_fund = FactoryBot.create(:fund, entity_id: @fund.entity_id, name: fund_name)
  doc = create_fund_document(other_fund, name: doc_name, folder_path: "")
  share_document_with_investor(doc, @investor)
  # Guard: the LP can see it, so leaving it out of a search can only be the fund-tree scoping
  expect(Document.for_investor(@investor_user, @fund.entity_id).exists?(id: doc.id)).to be(true)
end

When('I open the Documents section of the fund page as the investor') do
  visit(fund_path(@fund))
  # The LP fund page is an accordion; the Documents frame is lazy and loads once it is expanded
  find("#docs-tab button.accordion-button").click
  expect(page).to have_css("#collapseDocuments #documents_search", wait: 15)
  expect(page).to have_css("#documents_frame #docs_index", wait: 15)
end

When('I search the documents panel for {string}') do |term|
  # Typing submits the form after a short pause (documents_search_controller), no button needed
  within("#documents_search") { fill_in("search", with: term) }
end

When('I clear the documents panel search') do
  find("#documents_search button[aria-label='Clear search']").click
end

Then('the documents panel title should be {string}') do |title|
  expect(page).to have_css("#documents_frame #docs_index h4", text: title, wait: 15)
end

Then('the documents panel should list exactly {string}') do |names|
  expected = split_names(names)
  expect(page).to have_css("#documents_frame #docs_index", wait: 15)
  # Retry until the frame has swapped in the new list (search is debounced and async)
  page.document.synchronize(15) do
    actual = documents_panel_names
    raise Capybara::ExpectationNotMet, "Expected #{expected.inspect}, got #{actual.inspect}" unless actual.sort == expected.sort
  end
end

Then('the documents panel should list exactly {string} in that order') do |names|
  expected = split_names(names)
  expect(page).to have_css("#documents_frame #docs_index", wait: 15)
  page.document.synchronize(15) do
    actual = documents_panel_names
    raise Capybara::ExpectationNotMet, "Expected #{expected.inspect} in order, got #{actual.inspect}" unless actual == expected
  end
end

Then('the document {string} should show the folder {string}') do |doc_name, folder_name|
  doc = Document.find_by!(name: doc_name, entity_id: @fund.entity_id)
  # Tree-wide lists print the doc's folder under its name
  within("#documents_frame #document_#{doc.id} td.text-col") do
    expect(page).to have_css("small.text-muted", text: folder_name)
  end
end

Then('the documents panel should show the empty message {string}') do |message|
  expect(page).to have_css("#documents_frame #documents_empty", text: message, wait: 15)
end

Then("searching the entity's documents for {string} should return exactly {string}") do |term, names|
  actual = Document.where(entity_id: @fund.entity_id).name_or_tags_matching(term).pluck(:name)
  expect(actual.sort).to eq(split_names(names).sort)
end
