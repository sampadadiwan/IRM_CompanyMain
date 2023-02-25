class ImportInvestorAdvisorService
  include Interactor::Organizer

  organize ImportPreProcess, ImportInvestorAdvisor, ImportPostProcess
end
