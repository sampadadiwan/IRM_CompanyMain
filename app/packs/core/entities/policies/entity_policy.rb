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

  def dashboard?
    true
  end

  def search?
    true
  end

  # Any signed-in user may open a company's page (B1). Investors land on their GP's page after
  # requesting access, and advisors and LPs open it from their portal. What they see there is
  # decided by full_details?: an unrelated user gets only the public profile (name, logo, type,
  # website). The old body read "own entity or not own entity", i.e. always true, and the page
  # showed every visitor the company's tax id and primary email.
  # Worked examples B1-X, B1-H — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  def show?
    true
  end

  # Tax id, primary email and the other non-public fields: the company's own users (and a group
  # parent), support, anyone who is a stakeholder user AT this company (its LPs' contacts), an
  # advisor holding a grant on it, and staff of a company that has it as a stakeholder (a GP
  # looking at its LP).
  def full_details?
    return true if user.entity_id == record.id || support?
    return true if user.entity_type == "Group Company" && user.entity&.child_ids&.include?(record.id)
    return true if InvestorAccess.exists?(user_id: user.id, entity_id: record.id)
    return true if InvestorAdvisor.exists?(user_id: user.id, entity_id: record.id)

    Investor.exists?(entity_id: user.entity_id, investor_entity_id: record.id)
  end

  def create?
    support?
  end

  def new?
    update?
  end

  def update?
    ((user.entity_id == record.id) && user.has_cached_role?(:company_admin) && !user.investor_advisor?) || support?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # Off-boarding a client is a CapHive support action only — company admins must never be able to
  # switch off their own entity. Hidden once the entity is already deactivated.
  def deactivate?
    user.has_cached_role?(:support) && record.active?
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

  def db_dump?
    update? && record.entity_setting.db_dumps_enable
  end

  def permissioned_employee?(perm = nil)
    if perm.nil? || perm == :read
      user.entity_id == record.id
    else
      user.entity_id == record.id && user.has_cached_role?(:company_admin)
    end
  end
end
