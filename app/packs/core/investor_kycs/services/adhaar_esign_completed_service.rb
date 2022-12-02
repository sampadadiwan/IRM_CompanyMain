class AdhaarEsignCompletedService
  include Interactor::Organizer

  organize RetrieveEsignFile, UpdateEsignOwner, UpdateEsignCompleted, NotifyEsignUsers
end
