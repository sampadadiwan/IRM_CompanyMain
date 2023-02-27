class ImportValuationService
  include Interactor::Organizer

  organize ImportPreProcess, ImportValuation, ImportPostProcess
end
