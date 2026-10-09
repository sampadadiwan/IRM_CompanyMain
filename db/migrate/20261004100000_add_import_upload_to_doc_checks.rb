# Document Checks can be imported with ImportUpload (the setup page's Export file, edited and uploaded back).
# ImportUpload#imported_data lists — and Delete Imported Data destroys — the rows an upload created, found by
# this column; checks entered on the setup page leave it empty.
# See openspec/changes/document-checks/design.md (card ① Setup — Export and import). Worked example H15.
class AddImportUploadToDocChecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :doc_checks, :import_upload, null: true, foreign_key: false, index: true,
                                               comment: "The ImportUpload that created this check, if any"
  end
end
