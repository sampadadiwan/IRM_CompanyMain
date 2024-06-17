class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        # Give access to all the KYCs for the investor, where he has investor_accesses approved
        scope.where('investors.investor_entity_id': user.entity_id).joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
      elsif user.entity_type == "Group Company" || user.has_cached_role?(:company_admin)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee)
        # We cant show them all the KYCs, only the ones for the funds they have been permissioned
        fund_ids = Fund.for_employee(user).pluck(:id)
        scope.joins(capital_commitments: :fund).where('funds.id': fund_ids)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_kycs
  end

  def bulk_actions?
    index?
  end

  def show?
    user.enable_kycs && (
      (belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read)) ||
      user.entity_id == record.investor.investor_entity_id
    )
  end

  def create?(emp_perm = :create)
    (belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, emp_perm)) ||
      user.entity_id == record.investor&.investor_entity_id
  end

  def generate_docs?
    belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read)
  end

  def new?
    create?
  end

  def toggle_verified?
    belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :approve)
  end

  def send_kyc_reminder?
    user.enable_kycs && belongs_to_entity?(user, record)
  end

  def send_kyc_reminder_to_all?
    user.enable_kycs && user.curr_role == "employee"
  end

  def import?
    user.enable_kycs && user.curr_role == "employee"
  end

  def ckyc_or_kra_enabled?
    record.entity.entity_setting.ckyc_or_kra_enabled?
  end

  def generate_new_aml_report?
    toggle_verified?
  end

  def assign_kyc_data?
    belongs_to_entity?(user, record)
  end

  def compare_kyc_datas?
    belongs_to_entity?(user, record)
  end

  def generate_new_kyc_data?
    belongs_to_entity?(user, record)
  end

  def update?
    (create?(:update) || support?) && !record.verified
  end

  # Used to send notification to fund that kyc needs updates
  def send_notification?
    record.investor.investor_entity_id == user.entity_id && record.verified
  end

  def edit?
    update?
  end

  def destroy?
    create?(:destroy) && !record.verified
    belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :destroy)
  end
end
