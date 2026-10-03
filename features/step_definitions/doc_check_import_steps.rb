# Steps for Document Checks export (xlsx) and import (ImportUpload type DocCheck) —
# features/core/doc_check_import.feature. Self-contained: the Doc Questions import steps go when Doc Questions
# is retired (deploy 2).
# Worked examples H14, H15, E24, E25, X11, X12 in openspec/changes/document-checks/design.md#worked-examples

DOC_CHECK_IMPORT_COLUMNS = ["Id", *ImportDocCheck::STANDARD_HEADERS].freeze
DOC_CHECK_IMPORT_TYPES = [:string] * DOC_CHECK_IMPORT_COLUMNS.size

# The setup page's Export, downloaded with the signed-in browser session (the real controller and template),
# then read back as rows of strings
When("I export the document checks") do
  visit doc_checks_path
  href = find("#doc_check_export_btn")[:href]
  base64 = page.evaluate_async_script(<<~JS, href)
    const [url, done] = arguments
    fetch(url, { credentials: "same-origin" }).then((r) => r.arrayBuffer()).then((buf) => {
      let bin = ""
      new Uint8Array(buf).forEach((b) => { bin += String.fromCharCode(b) })
      done(btoa(bin))
    })
  JS
  path = Rails.root.join("tmp", "doc_checks_export_#{SecureRandom.hex(4)}.xlsx")
  File.binwrite(path, Base64.decode64(base64))
  sheet = Roo::Spreadsheet.open(path.to_s, extension: :xlsx).sheet(0)
  @export_rows = sheet.to_a.map { |row| row.map { |v| v.is_a?(Float) && v == v.to_i ? v.to_i.to_s : v.to_s } }
ensure
  FileUtils.rm_f(path) if path
end

Then("the export should have the columns {string}") do |columns|
  expect(@export_rows.first).to eq(columns.split(",").map(&:strip))
end

Then("the export should have {int} checks") do |count|
  expect(@export_rows.size - 1).to eq(count)
end

# "Fill in | DP ID | DP ID | 8 chars… | No | " — the columns after Id and Document
Then("the export row for {string} on {string} should be {string}") do |look_for, document, expected|
  row = export_row(document, look_for)
  expect(row[2..].map(&:strip)).to eq(expected.split("|", -1).map(&:strip))
end

When("in the export I change the tip of {string} on {string} to {string}") do |look_for, document, tip|
  export_row(document, look_for)[DOC_CHECK_IMPORT_COLUMNS.index("Tip")] = tip
end

# "PAN Card | Compare | PAN | PAN | The card's PAN |  | " — every column but Id (a new row has none)
When("in the export I add the row {string}") do |cells|
  @export_rows << ["", *cells.split("|", -1).map(&:strip)]
end

When("I import the edited export") do
  import_doc_check_rows(@export_rows.drop(1))
end

When("I import the document checks sample file") do
  @doc_check_import = run_doc_check_import(File.open(Rails.public_path.join('sample_uploads/doc_checks.xlsx')))
end

Given("another entity has a document check") do
  other = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @other_doc_check = DocCheck.create!(entity: other, record_type: "InvestorKyc", document_name: "CML",
                                      action: "question", look_for: "Is it stamped?")
end

# A table in the import's columns; Id "OTHER" stands for the other entity's check
When("I import the document check rows:") do |table|
  rows = table.hashes.map do |h|
    h = h.merge("Id" => @other_doc_check&.id.to_s) if h["Id"] == "OTHER"
    DOC_CHECK_IMPORT_COLUMNS.map { |column| h[column].to_s }
  end
  import_doc_check_rows(rows)
end

Then("the document check import should have {int} saved and {int} failed rows") do |saved, failed|
  @doc_check_import.reload
  expect([@doc_check_import.processed_row_count, @doc_check_import.failed_row_count]).to eq([saved, failed]),
                                                                                         -> { doc_check_import_results(@doc_check_import) }
end

Then("the document check import results should say {string}") do |text|
  expect(doc_check_import_results(@doc_check_import)).to include(text)
end

# "the entity should have {int} document checks" is in doc_checks_conversion_steps.rb

Then("the check {string} on {string} should have the tip {string}") do |look_for, document, tip|
  expect(DocCheck.find_by!(entity: @entity, document_name: document, look_for:).tip).to eq(tip)
end

Then("the check {string} on {string} should {string} the field {string}") do |look_for, document, action, field|
  check = DocCheck.find_by!(entity: @entity, document_name: document, look_for:)
  expect([check.action, check.field_name]).to eq([action.parameterize(separator: "_"), field])
end

# import_upload_id marks what an upload created (Delete Imported Data removes those); an edited check keeps
# whatever it had
Then("the check {string} on {string} should have been created by the import") do |look_for, document|
  expect(DocCheck.find_by!(entity: @entity, document_name: document, look_for:).import_upload_id).to eq(@doc_check_import.id)
end

Then("the check {string} on {string} should not have been created by the import") do |look_for, document|
  expect(DocCheck.find_by!(entity: @entity, document_name: document, look_for:).import_upload_id).to be_nil
end

Then("the other entity's document check should be unchanged") do
  expect(@other_doc_check.reload.attributes.except("updated_at")).to eq(@other_doc_check.attributes.except("updated_at"))
end

Then("the setup page should offer Export and Import") do
  visit doc_checks_path
  expect(find("#doc_check_export_btn")[:href]).to include("/doc_checks.xlsx")
  expect(find("#doc_check_import_btn")[:href]).to include("import_type%5D=DocCheck")
end

def export_row(document, look_for)
  row = @export_rows.find { |r| r[1] == document && r[3] == look_for }
  raise "No export row for #{look_for} on #{document}: #{@export_rows.inspect}" unless row

  row
end

# Rows in the import's columns → an xlsx → the real ImportUpload path (as the upload page)
def import_doc_check_rows(rows)
  require "caxlsx"
  tmp = Tempfile.new(["doc_checks_import", ".xlsx"])
  Axlsx::Package.new do |package|
    package.workbook.add_worksheet(name: "Document Checks") do |sheet|
      sheet.add_row(DOC_CHECK_IMPORT_COLUMNS)
      rows.each { |row| sheet.add_row(row, types: DOC_CHECK_IMPORT_TYPES) }
    end
    package.serialize(tmp.path)
  end
  @doc_check_import = run_doc_check_import(File.open(tmp.path))
ensure
  tmp&.close
  tmp&.unlink
end

def run_doc_check_import(file)
  upload = ImportUpload.create!(entity: @entity, owner: @entity, import_type: "DocCheck", name: "Document Checks import",
                                user_id: @user.id, import_file: file)
  ImportUploadJob.perform_now(upload.id)
  upload.reload
end

# The results xlsx attached back onto the upload — where each row's "Success" / "Error …" lands
def doc_check_import_results(upload)
  return upload.status.to_s if upload.import_results.blank?

  upload.import_results.open do |io|
    tmp = Tempfile.new(["doc_check_import_results", ".xlsx"])
    tmp.binmode
    tmp.write(io.read)
    tmp.flush
    text = Roo::Spreadsheet.open(tmp.path, extension: :xlsx).sheet(0).to_a.drop(1).map { |r| r.compact.join(" ") }.join("\n")
    tmp.close!
    return text
  end
end
