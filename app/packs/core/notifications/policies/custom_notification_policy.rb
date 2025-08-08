class CustomNotificationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee?
  end

  def mark_as_read?
    show?
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    # Templates can be edited only by support, for security reasons
    (record.is_erb ? support? : create?) &&
      (record.latest || record.email_method == "send_document" || record.for_type == "InvestorKyc") # Only the latest notification can be edited, but if it's a send_document, even the older ones can be edited, as users use multiple send_document notifications for different documents
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:create)
  end
end
