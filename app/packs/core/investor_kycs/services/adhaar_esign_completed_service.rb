class AdhaarEsignCompletedService
  include Interactor::Organizer

  organize RetrieveEsignFile, UpdateEsignOwner, NotifyEsignUsers
end
