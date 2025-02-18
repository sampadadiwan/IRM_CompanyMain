class EntityPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role.to_sym == :investor
        scope.for_investor(user)
      else
        scope.none
      end
    end

    def resolve_admin
      if user.has_cached_role?(:super)
        scope
      elsif user.has_cached_role?(:support)
        scope.joins(:support_client_mappings).where(support_client_mappings: { user_id: user.id, enabled: true }).merge(Entity.where_permissions(:enable_support))
      end
    end
  end

  def index?
    true
  end

  def merge?
    user.has_cached_role?(:support)
  end

  def report?
    true
  end

  def add_sebi_fields?
    (user.has_cached_role?(:company_admin) && !record.permissions.enable_sebi_fields?) || super_user?
  end

  def remove_sebi_fields?
    support?
  end

  def dashboard?
    true
  end

  def search?
    true
  end

  def show?
    if user.entity_id == record.id || support?
      true
    else
      user.entity_id != record.id
    end
  end

  def create?
    support?
  end

  def new?
    update?
  end

  def update?
    ((user.entity_id == record.id) && user.has_cached_role?(:company_admin)) || support?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def view_investments?
    user.entity_id == record.id || investment_access?
  end

  def investment_access?
    investor = Investor.for(user, record).first
    record.access_rights.investments.exists?(access_to_investor_id: investor.id)
  end

  def kpi_reminder?
    Entity.for_investor(user).collect(&:id).include?(record.id)
  end

  def permissioned_employee?(perm = nil)
    if perm.nil? || perm == :read
      user.entity_id == record.id
    else
      user.entity_id == record.id && user.has_cached_role?(:company_admin)
    end
  end
end
