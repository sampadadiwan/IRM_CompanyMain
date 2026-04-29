class UserGuidePolicy < ApplicationPolicy
  def index?
    user.present? && user.curr_role != "investor"
  end

  def show?
    user.present? && user.curr_role != "investor"
  end
end
