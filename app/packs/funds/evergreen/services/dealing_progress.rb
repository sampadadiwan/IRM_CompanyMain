# Where a dealing date stands on each step, from its own data. Shared by the dealing-date journey
# checks and by Close, so the step bar and the Close button never disagree.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingProgress
  def initialize(dealing_date)
    @dd = dealing_date
  end

  attr_reader :dd

  def subscriptions?
    dd.settled_or_closed? ? dd.subscription_fills.exists? : DealingOrder.exists?(dealing_date_id: dd.id, kind: "subscription", status: DealingOrder::OPEN_STATUSES)
  end

  def redemptions?
    dd.settled_or_closed? ? dd.redemption_fills.where("units > 0").exists? : DealingOrder.exists?(dealing_date_id: dd.id, kind: "redemption", status: DealingOrder::OPEN_STATUSES)
  end

  # Pre-funded: the cut-off has passed, or every subscription is already paid
  def money_collected_before?
    return true if dd.settled_or_closed? || dd.cutoff_passed?

    subs = DealingOrder.where(dealing_date_id: dd.id, kind: "subscription", status: DealingOrder::OPEN_STATUSES)
    subs.exists? && subs.all?(&:fully_paid?)
  end

  def nav_approved?
    return true if dd.settled_or_closed?

    classes = DealingOrder.where(dealing_date_id: dd.id, status: DealingOrder::OPEN_STATUSES).distinct.pluck(:unit_type)
    # Approved and, by Decision 4, newer than the NAV the class's previous dealing date used
    pricer = DealingPricer.new(dd)
    classes.any? && classes.all? { |ut| pricer.usable_nav?(pricer.pricing_nav(ut)) }
  end

  def confirmed?
    dd.settled_or_closed?
  end

  def instructions_sent?
    dd.subscription_fills.where(instructions_sent_at: nil).none?
  end

  def money_collected_after?
    dd.subscription_fills.includes(:capital_remittance).all? { |f| f.capital_remittance&.verified }
  end

  def units_allotted?
    confirmed? && dd.subscription_fills.where(fund_unit_id: nil).none?
  end

  def redemptions_paid?
    confirmed? && dd.redemption_fills.where("units > 0").includes(:capital_distribution_payment).all? { |f| f.capital_distribution_payment&.completed }
  end

  def units_cancelled?
    confirmed? && dd.redemption_fills.where("units > 0").where(fund_unit_id: nil).none?
  end

  # § Dealing-date documents: every settled fill with a template has its document
  def documents_generated?
    confirmed? && EvergreenDealingDocuments.to_generate(dd).empty?
  end

  # Every settled fill's email has gone out (straight away without a template, or at Approve & send)
  def documents_sent?
    confirmed? && settled_fills.where(document_sent_at: nil).none?
  end

  delegate :closed?, to: :dd

  # Close is allowed once every applicable step before it is done
  def closable?
    settled? && documents_sent?
  end

  # Every money / unit step is done but some contract note or advice is still unsent (X28)
  def waiting_for_documents?
    settled? && !documents_sent?
  end

  private

  # Confirmed, not closed, and every subscription and redemption step before the documents is done
  def settled?
    return false unless confirmed? && !closed?

    (!subscriptions? || (units_allotted? && (dd.pre_funded? || money_collected_after?))) &&
      (!redemptions? || (redemptions_paid? && units_cancelled?))
  end

  def settled_fills
    dd.dealing_fills.where.not(fund_unit_id: nil)
  end
end
