class ImportInvestorService
  include Interactor::Organizer

  organize ImportPreProcess, ImportInvestor, ImportPostProcess
end
