# Editing an open-ended fund's terms: fund update rights on an entity with evergreen funds switched on.
# Investors never see settings. (A fund's type is chosen on New Fund — evergreen-fund-on-create.)
# Worked examples H1, X1, X4, E47 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenFundSettingPolicy < EvergreenBasePolicy
  def show?
    entity_enabled? && fund_employee?(:read)
  end
end
