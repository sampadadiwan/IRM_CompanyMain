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

  ALWAYS_EDITABLE_EMAIL_METHODS = %w[send_document adhoc_notification adhoc_kyc_notification].freeze

  def update?
    # Templates can be edited only by support, for security reasons
    (record.is_erb ? support? : create?) &&
      (record.latest || ALWAYS_EDITABLE_EMAIL_METHODS.include?(record.email_method) || record.for_type == "InvestorKyc") # Only the latest notification can be edited, but adhoc/send_document notifications can have several non-latest ones in use at once, so those are always editable
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:create)
  end
end
