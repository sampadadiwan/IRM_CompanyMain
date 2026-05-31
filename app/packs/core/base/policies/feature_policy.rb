class FeaturePolicy < ApplicationPolicy
  def index?
    user.present? && user.support?
  end

  def show?
    user.present? && user.support?
  end
end
