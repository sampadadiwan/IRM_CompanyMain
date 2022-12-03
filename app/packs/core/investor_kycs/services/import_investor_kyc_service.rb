class ImportInvestorKycService
  include Interactor::Organizer

  organize ImportPreProcess, ImportInvestorKyc, ImportPostProcess
end
