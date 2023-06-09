class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[employee].include? user.curr_role.to_sym
        scope.where(entity_id: user.entity_id)
      else
        scope.where('investors.investor_entity_id': user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    user.entity_id == record.entity_id ||
      user.entity_id == record.investor.investor_entity_id
  end

  def create?
    (user.entity_id == record.entity_id) ||
      user.entity_id == record.investor.investor_entity_id
  end

  def new?
    create?
  end

  def toggle_verified?
    user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)
  end

  def generate_new_aml_report?
    toggle_verified?
  end

  def assign_kyc_data?
    user.entity_id == record.entity_id
  end

  def compare_kyc_datas?
    user.entity_id == record.entity_id
  end

  def generate_new_kyc_data?
    user.entity_id == record.entity_id
  end

  def update?
    create? && !record.verified
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
