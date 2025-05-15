class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        # Give access to all the KYCs for the investor, where he has investor_accesses approved
        scope.joins(:investor).where('investors.investor_entity_id': user.entity_id).joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
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
    permissioned_employee?(:investor_kyc_read) ||
      user.entity_id == record.investor&.investor_entity_id
  end

  def create?(emp_perm = :investor_kyc_create)
    permissioned_employee?(emp_perm) ||
      user.entity_id == record.investor&.investor_entity_id
  end

  def generate_docs?
    permissioned_employee?(:investor_kyc_update)
  end

  def new?
    create?
  end

  def toggle_verified?
    permissioned_employee?(:investor_kyc_approve)
  end

  def send_kyc_reminder?
    permissioned_employee?
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
    toggle_verified? && user.entity.entity_setting.aml_enabled
  end

  def assign_kyc_data?
    permissioned_employee?(:investor_kyc_update)
  end

  def compare_kyc_datas?
    permissioned_employee?
  end

  def generate_new_kyc_data?
    permissioned_employee?(:investor_kyc_update)
  end

  def update?
    (create?(:investor_kyc_update) || support?) && !record.verified
  end

  # Used to send notification to fund that kyc needs updates
  def send_notification?
    record.investor.investor_entity_id == user.entity_id && record.verified
  end

  def preview?
    permissioned_employee?(:investor_kyc_read)
  end

  def edit?
    update?
  end

  def destroy?
    create?(:investor_kyc_delete) && !record.verified
  end

  def permissioned_employee?(perm = nil)
    extended_permissioned_employee?(perm)
  end
end
