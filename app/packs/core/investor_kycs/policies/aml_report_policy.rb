class AmlReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[employee].include? user.curr_role.to_sym
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role.to_sym == :advisor
        scope.for_advisor(user)
      else
        scope.none
      end
    end
  end

  def index?
    user.entity.entity_setting.aml_enabled?
  end

  # investor can see investor kyc but not aml report
  def show?
    index? && user.entity_id == record.entity_id
  end

  def create?
    false
  end

  def advisor?
    record.entity.advisor?(user)
  end

  def new?
    create?
  end

  def generate_new?
    index? && user.entity_id == record.entity_id
  end

  def toggle_approved?
    show?
  end

  def update?
    false
  end

  def edit?
    false
  end

  def destroy?
    false
  end

  def aml_enabled
    user.entity.entity_setting.aml_enabled?
  end
end
