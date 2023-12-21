class ESignaturePolicy < ApplicationPolicy
  def index?
    user.enable_documents
  end

  def show?
    user.enable_documents &&
      belongs_to_entity?(user, record)
  end

  def create?
    belongs_to_entity?(user, record)
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
end
