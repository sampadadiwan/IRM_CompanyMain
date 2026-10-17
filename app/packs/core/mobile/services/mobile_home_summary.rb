# The LP mobile app's Home: one card per commitment (folio) and a short "To do" list.
#
# The card figures are the website's own: the closed-ended card reads the same four columns
# capital_commitments/_card shows (committed, called, distributed, due), and the evergreen card
# reads the same EvergreenUnitRegister row evergreen/funds/_lp_card shows. Nothing is
# recomputed here, so the app and website agree by construction (lp-mobile-app H4, E17).
#
# Everything is read through the caller's Pundit scopes, so Home shows exactly what the website
# would (design card ④).
class MobileHomeSummary
  TODO_LIMIT = 20

  # @param scope [#call] the controller's policy_scope, e.g. ->(klass) { policy_scope(klass) }
  def initialize(user:, scope:)
    @user = user
    @scope = scope
  end

  def call
    { todo: capital_call_todos + signature_todos, cards: }
  end

  def cards
    # H4, E16 (one card per folio), E29 (several fund managers — the app groups by entity_name)
    commitments.map { |cc| cc.fund.evergreen? ? evergreen_card(cc) : closed_card(cc) }
  end

  private

  attr_reader :user, :scope

  def commitments
    @commitments ||= scope.call(CapitalCommitment)
                          .includes(:entity, fund: :evergreen_fund_setting)
                          .order(:entity_id, :fund_id, :id)
                          .to_a
  end

  # The four figures on the website's capital_commitments/_card (E28: all zero before any call)
  def closed_card(cc)
    committed = cc.committed_amount
    called = cc.call_amount
    {
      kind: "closed", commitment_id: cc.id, fund_id: cc.fund_id, fund_name: cc.fund.name,
      entity_name: cc.entity.name, folio_id: cc.folio_id, currency: committed.currency.iso_code,
      committed: MobileMoney.call(committed), called: MobileMoney.call(called),
      called_pct: committed.zero? ? 0 : ((called.cents.to_d / committed.cents) * 100).round(1).to_f,
      due: MobileMoney.call(cc.due_amount), distributed: MobileMoney.call(cc.distribution_amount)
    }
  end

  # E17 — the evergreen card's figures, from the same EvergreenUnitRegister row the website uses
  def evergreen_card(cc)
    row = EvergreenUnitRegister.new(cc.fund, investor_ids: [cc.investor_id]).rows.find { |r| r.folio.id == cc.id }
    currency = cc.fund.currency
    {
      kind: "evergreen", commitment_id: cc.id, fund_id: cc.fund_id, fund_name: cc.fund.name,
      entity_name: cc.entity.name, folio_id: cc.folio_id, currency:,
      units: (row&.units || 0).to_d.round(4).to_s,
      value: row&.nav ? MobileMoney.cents(row.value_cents, currency) : nil,
      gain: row&.nav ? MobileMoney.cents(row.value_cents - row.cost_cents, currency) : nil,
      gain_pct: row&.gain_pct&.to_f,
      nav_per_unit: row&.nav ? MobileMoney.cents(row.nav.nav_per_unit_cents, currency) : nil,
      nav_date: row&.nav&.nav_date
    }
  end

  # Unpaid capital calls, earliest due date first (E18: Paid / Overpaid drop off; Overdue stays)
  def capital_call_todos
    scope.call(CapitalRemittance)
         .where(status: %w[Pending Overdue])
         .joins(:capital_call).includes(:capital_call, :fund)
         .order("capital_calls.due_date ASC, capital_remittances.id ASC")
         .limit(TODO_LIMIT)
         .map do |rem|
           { type: "capital_call", id: rem.id, title: rem.capital_call.name, fund_name: rem.fund.name,
             amount: MobileMoney.call(rem.due_amount), due_date: rem.capital_call.due_date, status: rem.status,
             link: "/capital-calls/#{rem.id}" }
         end
  end

  # Documents waiting for THIS user's signature
  def signature_todos
    MobileDocuments.new(user:, scope:).awaiting_signature.limit(TODO_LIMIT).map do |doc|
      { type: "signature", id: doc.id, title: doc.name, link: "/documents/#{doc.id}" }
    end
  end
end
