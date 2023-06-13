class ImportOfferDocsService
  include Interactor::Organizer

  organize ImportUnzipFile, ImportPreProcess, ImportOfferDocs, ImportPostProcess
end
