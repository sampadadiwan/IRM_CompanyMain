# The phone API's "about me" endpoints: a signed-in user may read and change only their own
# profile summary and push categories (lp-mobile-app design card ④).
class MobileSelfPolicy < ApplicationPolicy
  def show_self?
    record.id == user.id
  end

  def update_self?
    record.id == user.id
  end
end
