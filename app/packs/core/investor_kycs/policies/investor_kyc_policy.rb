class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company" || user.has_cached_role?(:company_admin)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee)
        # We cant show them all the KYCs, only the ones for the funds they have been permissioned
        fund_ids = Fund.for_employee(user).pluck(:id)
        scope.joins(investor: [capital_commitments: :fund]).where('funds.id': fund_ids)
      else
        scope.where('investors.investor_entity_id': user.entity_id)
      end
    end
  end

  def index?
    user.enable_kycs
  end

  def show?
    user.enable_kycs && (
      (belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read)) ||
      user.entity_id == record.investor.investor_entity_id
    )
  end

  def create?(emp_perm = :create)
    (
      (belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, emp_perm)) ||
      user.entity_id == record.investor&.investor_entity_id
    )
  end

  def generate_docs?
    (belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read))
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
    user.enable_kycs
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
    create?(:update) && !record.verified
  end

  def edit?
    update?
  end

  def destroy?
    create?(:destroy) && !record.verified
  end
end
