# ImportUpload type "DocCheck": the setup page's Export file, edited and uploaded back (ImportDocCheck).
# See openspec/changes/document-checks/design.md (card ① Setup — Export and import).
class ImportDocCheckService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDocCheck)
  step :save_results_file
end
