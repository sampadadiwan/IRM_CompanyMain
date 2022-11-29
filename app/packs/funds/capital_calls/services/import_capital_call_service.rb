class ImportCapitalCallService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalCall, ImportPostProcess
end
