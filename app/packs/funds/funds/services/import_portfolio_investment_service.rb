class ImportPortfolioInvestmentService
  include Interactor::Organizer

  organize ImportPreProcess, ImportPortfolioInvestment, ImportPostProcess
end
