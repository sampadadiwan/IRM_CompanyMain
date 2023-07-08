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
    create?
  end

  def edit?
    update? && !record.owner.sent_for_esign && record.status.nil?
  end

  def destroy?
    update?
  end
end
