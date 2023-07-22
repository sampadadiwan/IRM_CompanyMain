class ImportOptionsCustomDataService
  include Interactor::Organizer

  organize ImportPreProcess, ImportOptionsCustomData, ImportPostProcess
end
