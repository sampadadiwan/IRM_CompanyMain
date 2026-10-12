# The evergreen settings form's fields → EvergreenFundSetting attributes. Shared by Evergreen Settings
# (edit an open-ended fund's terms) and New Fund (create an open-ended fund with its terms).
# Worked examples H1, E6 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples
module EvergreenSettingParams
  extend ActiveSupport::Concern

  # X4, X5: a fund's type is fixed at creation
  TYPE_FIXED_MESSAGE = "A fund's type is chosen when it is created and can't be changed".freeze

  SETTING_FIELDS = %i[subscription_calendar redemption_calendar dealing_day dealing_day_n payment_timing pay_after_days
                      subscription_cutoff_days unready_handling order_journeys redemption_settlement_days notice_days
                      lock_up_months lock_up_type gate_pct gate_level gate_period gate_method investor_gate_pct
                      min_initial_subscription min_additional_subscription min_holding cash_entry_name unit_term
                      other_assets_entry_name other_liabilities_entry_name mgmt_fee_paid_entry_name perf_fee_paid_entry_name
                      fund_close_name payment_instructions preset early_fee_pct early_fee_schedule
                      subscription_dates_text redemption_dates_text].freeze
  CLASS_FIELDS = %i[id unit_type initial_price perf_fee_model perf_fee_pct hurdle_pct hurdle_type crystallisation notice_days
                    lock_up_months lock_up_type early_fee_pct min_initial_subscription min_additional_subscription min_holding
                    class_expense_entry_name class_expense_paid_entry_name].freeze

  private

  def evergreen_setting_permitted
    params.fetch(:evergreen_fund_setting, {}).permit(*SETTING_FIELDS, redemption_forms: [], class_terms: CLASS_FIELDS,
                                                                      notifications: EvergreenFundSetting::NOTIFICATIONS.keys + EvergreenFundSetting::NOTIFICATION_NUMBERS.keys)
  end

  # Form fields → model attributes (fee %, schedule text and date lists become JSON)
  def evergreen_setting_attributes
    attrs = evergreen_setting_permitted.to_h.symbolize_keys
    fee_pct = attrs.delete(:early_fee_pct)
    schedule = attrs.delete(:early_fee_schedule)
    attrs[:early_redemption_fee] = EvergreenFormParsing.early_fee(fee_pct, schedule)
    attrs[:subscription_dates] = EvergreenFormParsing.dates(attrs.delete(:subscription_dates_text))
    attrs[:redemption_dates] = EvergreenFormParsing.dates(attrs.delete(:redemption_dates_text))
    attrs[:redemption_forms] = Array(attrs[:redemption_forms]).compact_blank
    # Notification switches arrive as "0"/"1"; the two numbers stay as entered (§ Notifications)
    if attrs[:notifications]
      # Keep only values that differ from the defaults, so a default changed later still reaches this fund
      attrs[:notifications] = attrs[:notifications].to_h.to_h do |k, v|
        EvergreenFundSetting::NOTIFICATION_NUMBERS.key?(k) ? [k, v.presence] : [k, ActiveModel::Type::Boolean.new.cast(v)]
      end
      attrs[:notifications].reject! do |k, v|
        v.nil? || (EvergreenFundSetting::NOTIFICATIONS.key?(k) ? v == EvergreenFundSetting::NOTIFICATIONS[k][1] : v.to_s.to_d == EvergreenFundSetting::NOTIFICATION_NUMBERS[k].to_d)
      end
    end
    # Class rows arrive indexed ({"0" => {...}}) from the form
    class_rows = attrs[:class_terms].is_a?(Hash) ? attrs[:class_terms].values : Array(attrs[:class_terms])
    attrs[:class_terms] = class_rows.map do |c|
      c = c.to_h.symbolize_keys
      c[:early_redemption_fee] = EvergreenFormParsing.early_fee(c.delete(:early_fee_pct), nil, allow_nil: true)
      c.transform_values { |v| v == "" ? nil : v }
    end
    attrs
  end

  def evergreen_setting_attributes_for_update
    attrs = evergreen_setting_attributes
    class_terms = attrs.delete(:class_terms)
    # A saved class keeps its unit type (it can't be renamed here); a new row (Edit Fund, a unit type just
    # added) has no id yet and needs its unit type to be created
    if class_terms.present?
      # (a new class also belongs to the fund's entity and fund, as EvergreenEnable sets on create — H4)
      attrs[:evergreen_class_terms_attributes] = class_terms.map do |c|
        c[:id].present? ? c.except(:unit_type) : c.merge(entity_id: @fund.entity_id, fund_id: @fund.id)
      end
    end
    attrs
  end
end
