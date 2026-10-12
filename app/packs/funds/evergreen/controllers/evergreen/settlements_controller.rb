# The evergreen settlement page: a dealing date's capital call or distribution shown with evergreen
# labels, linked back to its dealing date, with no manual unit buttons (spec GP › Settlement record
# opened, No manual unit buttons). The existing call / distribution pages redirect here for these records.
# Worked example H36 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class SettlementsController < BaseController
    def show
      if params[:kind] == "redemption"
        @record = @fund.capital_distributions.find(params[:id])
        @dealing_date = DealingDate.find_by!(redemption_distribution_id: @record.id)
        @rows = @record.capital_distribution_payments.includes(:capital_commitment, :investor)
      else
        @record = @fund.capital_calls.find(params[:id])
        @dealing_date = DealingDate.find_by!(subscription_call_id: @record.id)
        @rows = @record.capital_remittances.includes(:capital_commitment, :investor)
      end
      authorize @dealing_date, :show?
    end
  end
end
