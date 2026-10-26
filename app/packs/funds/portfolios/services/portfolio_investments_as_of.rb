# Values portfolio investments as of one date, for the portfolio report builders (fmv, cost of remaining, cost of sold).
#
# PortfolioInvestment#as_of recomputes the record in place and freezes it, so a record valued for one date can never be
# valued for another. Each call therefore loads its own records from a relation, and refuses records that are already
# loaded. The sold and transferred quantities of all the buys are read in grouped queries first, the way
# AggregatePortfolioInvestment#as_of does, instead of by each buy. X1, X3
class PortfolioInvestmentsAsOf
  # @param scope [ActiveRecord::Relation] PortfolioInvestments not loaded yet, e.g. one fund's investments up to a date
  # @param date [Date]
  # @return [Array<PortfolioInvestment>] valued and frozen: read them with Enumerable methods only
  def self.call(scope, date)
    raise ArgumentError, "scope must be a PortfolioInvestment relation that is not loaded yet" unless scope.is_a?(ActiveRecord::Relation) && !scope.loaded?
    raise ArgumentError, "date must be a Date" unless date.is_a?(Date)

    records = scope.to_a
    bought = records.select(&:buy?)
    PortfolioInvestment.with_buy_quantities(bought, date:)
    PortfolioInvestment.with_net_quantities_on(bought, date) unless date == Time.zone.today
    records.map { |pi| pi.as_of(date) }
  end
end
