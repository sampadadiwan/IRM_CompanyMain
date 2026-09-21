Then('there should be {string} doc questions for the entity') do |count|
  DocQuestion.where(entity_id: @entity.id).count.should == count.to_i
end

Then('the doc question {string} should have type {string} for class {string} document name {string} tags {string}') do |question, qtype, for_class, document_name, tags|
  dq = DocQuestion.where(entity_id: @entity.id, question: question).first
  expect(dq).not_to be_nil, "Expected a doc question asking '#{question}'"
  dq.qtype.should == qtype
  dq.for_class.should == for_class
  dq.document_name.to_s.should == document_name
  dq.tags.to_s.should == tags
end

Then('the doc question {string} should have extract to {string}') do |question, response_hint|
  dq = DocQuestion.where(entity_id: @entity.id, question: question).first
  expect(dq).not_to be_nil, "Expected a doc question asking '#{question}'"
  dq.response_hint.should == response_hint
end

# The import button sends no owner params, so ImportUploadsController#new defaults the
# owner to the entity - which is what WithDocQuestions#doc_questions looks the questions
# up by. An owner of anything else makes the imported questions invisible to the LLM.
Then('every imported doc question should be owned by the entity') do
  DocQuestion.where(entity_id: @entity.id).each do |dq|
    dq.owner_type.should == "Entity"
    dq.owner_id.should == @entity.id
  end
end

Then('re-importing {string} for {string} should fail with {string} on every row') do |file, type, message|
  iu = ImportUpload.create!(
    entity: @entity,
    owner: @entity,
    import_type: type,
    name: "Re-import #{type}",
    user_id: @user.id,
    import_file: File.open(File.absolute_path("./public/sample_uploads/#{file}"))
  )
  ImportUploadJob.perform_now(iu.id)
  iu.reload

  iu.processed_row_count.should == 0
  iu.failed_row_count.should == iu.total_rows_count
  import_results_text(iu).should include(message)
end

# The download carries an Id column, so a downloaded sheet edited and sent back must
# update the questions it came from. Without that, an edited question text no longer
# matches anything and the import quietly creates a second copy.
When('I re-import the doc questions carrying their Ids, with the question text edited') do
  rows = DocQuestion.where(entity_id: @entity.id).order(:id).map do |dq|
    [dq.id, dq.question, dq.qtype, dq.for_class, dq.document_name, dq.tags, dq.response_hint]
  end
  @edited_doc_question_id = rows.first[0]
  @edited_doc_question_text = "#{rows.first[1]} (edited)"
  rows.first[1] = @edited_doc_question_text
  @first_import_upload_id = DocQuestion.find(@edited_doc_question_id).import_upload_id

  import_doc_question_rows(rows)
end

When('I re-import the doc questions carrying an Id that does not exist') do
  missing_id = DocQuestion.maximum(:id).to_i + 1000
  import_doc_question_rows([[missing_id, "A question with a bogus Id?", "validation", "Investor", "Doc A", "", ""]])
end

Then('the edited doc question should have been saved') do
  DocQuestion.find(@edited_doc_question_id).question.should == @edited_doc_question_text
end

# import_upload_id is what Delete Imported Data destroys, so an upload that only edited
# a question must not take ownership of it away from the upload that created it.
Then('the edited doc question should still belong to the upload that created it') do
  DocQuestion.find(@edited_doc_question_id).import_upload_id.should == @first_import_upload_id
end

Then('the import upload should have {string} processed and {string} failed rows') do |processed, failed|
  @import_upload.reload
  @import_upload.processed_row_count.should == processed.to_i
  @import_upload.failed_row_count.should == failed.to_i
end

Then('the import results should mention {string}') do |message|
  import_results_text(@import_upload).should include(message)
end

Then('the import upload status should mention {string}') do |message|
  @import_upload.reload.status.to_s.should include(message)
end

# Builds an xlsx shaped like the DocQuestions download - Id first - and runs it through
# the real import path, so the round trip is exercised end to end rather than stubbed.
def import_doc_question_rows(rows)
  require "caxlsx"
  tmp = Tempfile.new(["doc_questions_roundtrip", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Doc Questions") do |ws|
      ws.add_row(["Id", "Question*", "Type*", "For*", "Document Name", "Tags", "Extract To"])
      rows.each { |r| ws.add_row(r) }
    end
    p.serialize(tmp.path)
  end

  @import_upload = ImportUpload.create!(entity: @entity, owner: @entity, import_type: "DocQuestion",
                                        name: "Round trip DocQuestion", user_id: @user.id,
                                        import_file: File.open(tmp.path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
ensure
  tmp&.close
  tmp&.unlink
end

# Reads the results xlsx the importer attaches back onto the upload. That sheet is the
# only place a per-row error message lands, so it is what a failure assertion has to read.
def import_results_text(import_upload)
  return "" if import_upload.import_results.blank?

  text = ""
  import_upload.import_results.open do |io|
    tmp = Tempfile.new(["import_results", ".xlsx"])
    tmp.binmode
    tmp.write(io.read)
    tmp.flush
    rows = []
    Roo::Spreadsheet.open(tmp.path).each_with_index do |row, idx|
      next if idx.zero?

      rows << row.compact.join(" ")
    end
    text = rows.join(" ")
    tmp.close
    tmp.unlink
  end
  text
end
