class DocumentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
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
      user.entity.enable_documents &&
        Document.for_investor(user, record.entity)
                .where("documents.id=?", record.id).first.present?
    end
  end

  def create?
    (user.entity_id == record.entity_id && user.entity.enable_documents)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
