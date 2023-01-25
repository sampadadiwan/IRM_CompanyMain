class ImportKycDocsService
  include Interactor::Organizer

  organize ImportUnzipFile, ImportPreProcess, ImportKycDocs, ImportPostProcess
end
