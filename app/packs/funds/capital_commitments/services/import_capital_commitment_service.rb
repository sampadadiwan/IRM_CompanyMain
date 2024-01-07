class ImportCapitalCommitmentService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalCommitment, ImportPostProcess
end
