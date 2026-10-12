# Creates an open-ended fund complete: the fund and its evergreen terms in one transaction, or nothing.
# A fund's type is chosen once, on New Fund; there is no later switch (evergreen-fund-on-create ⑤).
# Worked examples H1, X1, X2, X3 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples
class EvergreenFundCreate < Trailblazer::Operation
  step :check_unit_types
  step :create

  NO_UNIT_TYPES = "Add at least one unit class for an open-ended fund".freeze

  # X1: an open-ended fund is built on unit classes
  def check_unit_types(ctx, fund:, **)
    return true if fund.unit_types_list.present?

    fund.errors.add(:unit_types, :blank, message: NO_UNIT_TYPES)
    ctx[:errors] = [NO_UNIT_TYPES]
    false
  end

  # H1: fund, settings, class terms and the evergreen journeys together; X2, X3: any failure rolls all
  # of it back and the form is shown again with the messages
  def create(ctx, fund:, setting_params:, current_user:, **)
    errors = []
    ActiveRecord::Base.transaction do
      unless fund.save
        errors.concat(fund.errors.full_messages)
        raise ActiveRecord::Rollback
      end
      result = EvergreenEnable.call(fund:, current_user:, params: setting_params)
      ctx[:evergreen_fund_setting] = result[:evergreen_fund_setting]
      unless result.success?
        errors.concat(Array(result[:evergreen_fund_setting]&.errors&.full_messages.presence || result[:errors]))
        raise ActiveRecord::Rollback
      end
    end
    ctx[:errors] = errors
    errors.empty?
  end
end
