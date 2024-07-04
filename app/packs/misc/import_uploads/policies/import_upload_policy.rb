class ImportUploadPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_import_uploads
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def delete_data?
    update?
  end
end
