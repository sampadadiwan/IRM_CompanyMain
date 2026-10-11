# Records a new contract and its trade event (premium paid for a long, received for a short).
# Worked examples H11, H12, E48 — openspec/changes/fund-market-data/business-rules.md
class DerivativeContractCreator
  def self.call(contract:, premium: nil)
    new(contract, premium).call
  end

  def initialize(contract, premium)
    @contract = contract
    @premium = premium
  end

  # Returns true when saved; errors are on the contract
  def call
    DerivativeContract.transaction do
      # Premium is entered as a positive amount; a long pays it (cost +), a short receives it (cost −)
      amount = BigDecimal(@premium.presence || 0) * 100
      @contract.premium_cents = @contract.long? ? amount : -amount
      @contract.name = default_name if @contract.name.blank?
      raise ActiveRecord::Rollback unless @contract.save

      result = DerivativeEventRecorder.call(contract: @contract, idempotency_key: "trade:#{@contract.id}",
                                            params: { event_type: "trade", event_date: @contract.trade_date, amount_cents: -@contract.premium_cents })
      unless result.success?
        result.errors.each { |e| @contract.errors.add(:base, e) }
        raise ActiveRecord::Rollback
      end
      true
    end || false
  end

  private

  def default_name
    parts = [@contract.underlying_name.presence || @contract.underlying_instrument&.name, @contract.strike&.to_d&.to_i,
             @contract.option_type&.upcase&.first, DerivativeContract::TYPE_LABELS[@contract.contract_type]]
    parts.compact.join(" ").truncate(100)
  end
end
