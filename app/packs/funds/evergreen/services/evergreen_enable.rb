# Makes a fund evergreen: the entity must have evergreen funds switched on and the fund at least one
# unit class. Creates the fund's settings and one class-terms row per unit class, then seeds the
# dealing-date and order journey templates for the entity (idempotent).
# Worked examples H1, X1 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenEnable < Trailblazer::Operation
  step :check_allowed
  step :build_setting
  step :save
  step :seed_journeys

  def check_allowed(ctx, fund:, **)
    unless fund.entity.permissions.enable_evergreen_funds?
      ctx[:errors] = "Evergreen funds are not switched on for this entity"
      return false
    end
    if fund.unit_types_list.blank?
      # Worked example X1
      ctx[:errors] = "Add a unit class first"
      return false
    end
    if fund.evergreen_fund_setting&.persisted?
      ctx[:errors] = "This fund is already evergreen"
      return false
    end
    true
  end

  def build_setting(ctx, fund:, current_user:, params: {}, **)
    setting = fund.build_evergreen_fund_setting(params.except(:class_terms))
    setting.entity_id = fund.entity_id
    setting.enabled_by = current_user
    # One class-terms row per unit class, with any per-class values supplied by the form
    class_params = Array(params[:class_terms]).index_by { |c| c[:unit_type].to_s }
    fund.unit_types_list.each do |unit_type|
      attrs = (class_params[unit_type] || {}).except(:unit_type)
      setting.evergreen_class_terms.build(attrs.merge(entity_id: fund.entity_id, fund_id: fund.id, unit_type:))
    end
    ctx[:evergreen_fund_setting] = setting
  end

  def save(ctx, evergreen_fund_setting:, fund:, **)
    ok = evergreen_fund_setting.save
    ctx[:errors] = evergreen_fund_setting.errors.full_messages.join(", ") unless ok
    fund.reset_evergreen_cache
    ok
  end

  # Journey templates are seeded per entity, once; later phases register the setups here.
  def seed_journeys(_ctx, fund:, **)
    EvergreenJourneys.seed(fund.entity)
    true
  end
end
