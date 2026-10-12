# Investors tab: the unit register (proposal GP-6), downloadable.
# Worked example H35 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class InvestorsController < BaseController
    before_action :require_evergreen!

    def index
      authorize @fund, :show?, policy_class: EvergreenFeesPolicy
      @register = EvergreenUnitRegister.new(@fund).rows
      respond_to do |format|
        format.html
        format.xlsx { render xlsx: "index", filename: "#{@fund.name} unit register.xlsx" }
      end
    end
  end
end
