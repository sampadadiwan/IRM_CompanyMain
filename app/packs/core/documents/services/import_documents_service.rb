class ImportDocumentsService
  include Interactor::Organizer

  organize ImportUnzipFile, ImportDocuments, ImportPostProcess
end
