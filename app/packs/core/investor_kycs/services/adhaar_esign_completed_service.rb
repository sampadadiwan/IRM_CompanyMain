class AdhaarEsignCompletedService
  include Interactor::Organizer

  organize RetrieveEsignFile, UpdateEsignCompleted, UpdateEsignOwner, NotifyEsignUsers
end
