# Fees tab (proposal GP-7): management-fee accruals and payable by month, performance fee against the
# high-water mark, crystallisation history; seeds the "Management Fee on NAV" formula.
# Worked examples H27, E35, E38 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class FeesController < BaseController
    before_action :require_evergreen!

    def show
      authorize @fund, :show?, policy_class: EvergreenFeesPolicy
      @classes = @fund.unit_types_list
      @rows = EvergreenFeeSummary.new(@fund).rows
    end

    def seed_formula
      authorize @fund, :update?, policy_class: EvergreenFeesPolicy
      _, created = EvergreenFeeFormulaSeed.call(@fund)
      redirect_to evergreen_fees_path(@fund), notice: created ? "Management fee formula added" : "The management fee formula already exists"
    end
  end
end
