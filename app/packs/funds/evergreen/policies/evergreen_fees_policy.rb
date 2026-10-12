# The Fees tab and seeding the management-fee formula: GP users of the fund.
class EvergreenFeesPolicy < EvergreenBasePolicy
  def show?
    entity_enabled? && fund_employee?(:read)
  end
end
