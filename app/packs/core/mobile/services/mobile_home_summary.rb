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
  # @param fund_manager_id [Integer, nil] the one GP entity Home shows (lp-mobile-multi-site
  #   design card ③); nil only for a user with no fund manager, whose Home is then empty anyway
  def initialize(user:, scope:, fund_manager_id: nil)
    @user = user
    @scope = scope
    @fund_manager_id = fund_manager_id
  end

  def call
    { fund_manager_id:, todo: capital_call_todos + signature_todos + approval_todos, cards: }
  end

  def cards
    # H4, E16 (one card per folio); one fund manager at a time (lp-mobile-multi-site MF-H1)
    commitments.map { |cc| cc.fund.evergreen? ? evergreen_card(cc) : closed_card(cc) }
  end

  private

  attr_reader :user, :scope, :fund_manager_id

  # The caller's Pundit scope, narrowed to the selected fund manager
  def scoped(klass)
    relation = scope.call(klass)
    fund_manager_id ? relation.where(entity_id: fund_manager_id) : relation
  end

  def commitments
    @commitments ||= scoped(CapitalCommitment)
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
    scoped(CapitalRemittance)
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

  # Approvals the GP sent that still wait for this investor's answer, soonest due first. Only
  # published approvals (the ones that notified the investor) and only while still answerable.
  def approval_todos
    # Only users whose approvals module is on can open one (ApprovalResponsePolicy#show?)
    return [] unless user.enable_approvals

    responses = scoped(ApprovalResponse).pending.joins(:approval)
                                        .where(approvals: { approved: true, due_date: Time.zone.today.. })
    responses.includes(:approval).order("approvals.due_date ASC, approval_responses.id ASC").limit(TODO_LIMIT).map do |response|
      { type: "approval", id: response.id, title: response.approval.title, due_date: response.approval.due_date,
        link: "/approvals/#{response.id}" }
    end
  end

  # Documents waiting for THIS user's signature
  def signature_todos
    MobileDocuments.new(user:, scope:, fund_manager_id:).awaiting_signature.limit(TODO_LIMIT).map do |doc|
      { type: "signature", id: doc.id, title: doc.name, link: "/documents/#{doc.id}" }
    end
  end
end
