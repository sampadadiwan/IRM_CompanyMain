# Who may record the fund's own figures while reviewing an allocation run.
#
# The same people who may read the Account Entries Period Report the figures are typed on:
# employees with funds enabled. Investors are excluded — these are the fund's working notes
# about its own books, not anything an investor should see or write.
class TieOutFigurePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "investor"
        scope.none
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def show? = fund_permitted?

  # Typing a figure writes a TieOutFigure and changes nothing in the ledger. A figure on a
  # locked run's date stays editable on purpose: locking protects the entries the engine
  # produced, not the fund's own notes about them.
  def create? = fund_permitted?
  def update? = fund_permitted?
  def destroy? = fund_permitted?

  private

  def fund_permitted?
    return false unless user.enable_funds && !user.curr_role_investor?
    return false unless belongs_to_entity?(user, record)

    record.fund.present? && FundPolicy.new(user, record.fund).period_report?
  end
end
