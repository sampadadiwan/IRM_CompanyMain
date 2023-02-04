class ImportAccountEntryService
  include Interactor::Organizer

  organize ImportPreProcess, ImportAccountEntry, ImportPostProcess
end
