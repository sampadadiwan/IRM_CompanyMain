class ImportCapitalRemittanceService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalRemittance, ImportPostProcess
end
