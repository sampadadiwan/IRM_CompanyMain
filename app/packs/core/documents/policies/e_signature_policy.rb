class ESignaturePolicy < ApplicationPolicy
  def index?
    user.enable_documents
  end

  def show?
    user.enable_documents &&
      belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.document)
  end

  def new?
    create?
  end

  def update?
    create? && !record.document.sent_for_esign
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  # Embedded signing: may this user sign this signature request inside the platform?
  #
  # Identity, not entity membership: the login email must equal the signer email, because an investor
  # signs a document that belongs to another entity (belongs_to_entity? would refuse them). The caller
  # reads ESignature#signing_state for "is it their turn"; this answers only "is it them, and is the
  # feature on for this document".
  #
  # A support user impersonating the signer cannot sign: a signature has to come from the person's own login.
  def sign?
    # Cheap identity checks first: on the Signatures tab every row asks, and only the viewer's own row
    # should go on to load the document's entity and settings.
    return false unless record.signable_by?(user)
    return false if user.support_user_id.present?

    document = record.document
    return false if document.blank? || document.provider_doc_id.blank?

    document.entity.permissions.enable_embedded_esign? &&
      document.entity.entity_setting&.esign_provider == "Digio"
  end

  # Reporting a result from the signing page needs the same identity. The state is not consulted:
  # Digio's own notification may already have moved it by the time the panel reports.
  def sign_result?
    sign?
  end
end
