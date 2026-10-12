class ExchangeRate < ApplicationRecord
  include ExchangeRateShared

  # A rate is entity-wide unless it belongs to one fund (fund-specific rates — only funds with
  # "Use fund-specific FX rates"). openspec fund-market-data — design card ③ (H21, E68–E72, X33, X34).
  belongs_to :owner, polymorphic: true, optional: true
  # The two rates a derived rate was built from (cross) or the one it reverses
  belongs_to :leg1, class_name: "ExchangeRate", optional: true
  belongs_to :leg2, class_name: "ExchangeRate", optional: true

  validate :owner_is_fund_using_own_rates
  validate :owner_rates_are_manual

  after_create_commit :ensure_latest

  # Keeps `latest` right and starts the work a new rate implies:
  # - derived rates start nothing (E25 — Edge case: derived rate starts no jobs)
  # - fair values are recomputed only in funds that accept this rate (E29); the job does the filtering
  # - the exchange-rate commitment adjustment reacts to manual rates only (E30); a fund's own rate
  #   adjusts only that fund (E72)
  def ensure_latest
    return unless latest

    # Clear the older `latest` row in this rate's source/owner group — derived rows too, so the
    # default "latest" list never shows two derived rates for one pair
    self.class.where(entity_id:, to:, from:, source:, owner_type:, owner_id:, latest: true).where.not(id:).update_all(latest: false)
    return if derived?
    return if import_upload_id.present?

    ExchangeRateCommitmentAdjustmentJob.perform_later(id) if manual? && entity.customization_flags.enable_exchange_rate_commitment_adjustment?
    ExchangeRatePortfolioInvestmentJob.perform_later(id)
  end

  # The fund this rate belongs to, when it is fund-specific
  def owner_fund
    owner if owner_type == "Fund"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[as_of decimal from latest notes owner_id provider rate rate_type source to updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  private

  # X33/X34 — Error case: a fund-specific rate must name a fund of this entity that uses its own rates
  def owner_is_fund_using_own_rates
    return if owner_type.blank?

    if owner_type != "Fund" || owner.nil? || owner.entity_id != entity_id
      errors.add(:owner, "Fund #{owner.try(:name) || owner_id} not found")
    elsif !owner.features.use_own_fx_rates?
      errors.add(:owner, "Fund #{owner.name} does not use fund-specific FX rates")
    end
  end

  # Fund-specific rates are always typed in or uploaded (the feed never writes them); derived rows
  # built from a fund's own leg also carry that fund as owner.
  def owner_rates_are_manual
    return if owner_type.blank? || source.in?(%w[manual derived])

    errors.add(:source, "must be Manual for a fund-specific rate")
  end
end
