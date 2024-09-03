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
    user.enable_import_uploads &&
      Pundit.policy(user, record.owner).permissioned_employee?
  end

  def create?
    user.enable_import_uploads &&
      Pundit.policy(user, record.owner).permissioned_employee?
  end

  def new?
    create?
  end

  def update?
    create?
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
