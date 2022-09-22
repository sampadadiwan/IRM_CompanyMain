class ImportInvestorAccessService
  include Interactor::Organizer

  organize ImportPreProcess, ImportInvestorAccess, ImportPostProcess
end
