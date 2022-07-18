class DocumentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      case user.curr_role
      when "consultant"
        scope.joins(:permissions).where("permissions.user_id=?", user.id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.entity.enable_documents
  end

  def show?
    if user.entity_id == record.entity_id && user.entity.enable_documents
      true
    else
      (user.entity.enable_documents && show_investor?) ||
        (record.owner && owner_policy.show?) ||
        allow_external?(:read)
    end
  end

  def create?
    (user.entity_id == record.entity_id && user.entity.enable_documents) ||
      (record.owner && owner_policy.update?)
    # || (record.owner && record.owner_type == "DealInvestor" && owner_policy.show?)
  end

  def new?
    create?
  end

  def update?
    create? ||
      (record.owner && owner_policy.update?) ||
      allow_external?(:write)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def show_investor?
    Document.for_investor(user, record.entity)
            .where("documents.id=?", record.id).first.present?
  end

  def owner_policy
    Pundit.policy(user, record.owner)
  end
end
