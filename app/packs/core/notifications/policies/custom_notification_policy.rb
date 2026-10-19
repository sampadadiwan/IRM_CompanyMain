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
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    permissioned_employee?(:create) && parent_in_users_firms?(record.owner)
  end

  # E: the fields this user may send. is_erb makes the body run as Ruby code when the email renders,
  # so only support may set it (the form shows its toggle only to support; this makes the server agree)
  def permitted_attributes
    fields = %i[subject body whatsapp for_type show_details entity_id owner_id owner_type attachment_password
                password_protect_attachment show_details_link email_method enabled to attachment_names tag
                latest_doc_only attachment_mandatory]
    fields << :is_erb if user.support?
    fields
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
