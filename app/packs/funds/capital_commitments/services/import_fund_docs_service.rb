class ImportFundDocsService
  include Interactor::Organizer

  organize ImportUnzipFile, ImportPreProcess, ImportFundDocs, ImportPostProcess
end
