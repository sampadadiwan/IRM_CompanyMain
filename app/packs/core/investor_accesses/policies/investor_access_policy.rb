class InvestorAccessPolicy < ApplicationPolicy
  def index?
    user.has_cached_role?(:company_admin)
    # !user.investor_advisor?
  end

  def show?
    user.has_cached_role?(:company_admin) &&
      (belongs_to_entity?(user, record) || user.entity_id == record.investor.investor_entity_id)
  end

  # SECURITY (finding M5): granting/editing investor access follows the authority to manage the
  # INVESTOR itself — anyone who can update the investor may create or update its access grants.
  # InvestorPolicy#update? already encodes the right scope: company admins, employees with
  # investor-update permission or explicit access to that investor, and support. This is more precise
  # than a blanket company_admin gate (and than the previous belongs_to_entity? gate, which let any
  # employee of the managing entity grant access). Self-service requests still go through
  # request_access? below, which forces approved=false so a requester cannot grant themselves access.
  def create?
    record.investor.present? && new_policy(record.investor).update?
  end

  def request_access?
    user.entity_id == record.investor.investor_entity_id && !record.approved
  end

  def new?
    create?
  end

  def update?
    record.investor.present? && new_policy(record.investor).update?
  end

  def approve?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end
end
