class ImportFundUnitService
  include Interactor::Organizer

  organize ImportPreProcess, ImportFundUnit, ImportPostProcess
end
