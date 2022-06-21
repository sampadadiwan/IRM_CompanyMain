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
      (user.entity.enable_documents &&
        Document.for_investor(user, record.entity)
                .where("documents.id=?", record.id).first.present?) || allow?(:read)
    end
  end

  def create?
    (user.entity_id == record.entity_id && user.entity.enable_documents)
  end

  def new?
    create?
  end

  def update?
    create? || allow?(:write)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
