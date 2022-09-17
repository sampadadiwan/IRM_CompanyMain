class SetupFundingRoundForPool
  include Interactor

  def call
    Rails.logger.debug "Interactor: SetupFundingRoundForPool called"

    if context.option_pool.present?
      option_pool = context.option_pool
      option_pool.funding_round = FundingRound.create(
        name: option_pool.name,
        currency: option_pool.entity.currency,
        entity_id: option_pool.entity_id,
        status: "Open",
        audit_comment: "#{context.audit_comment} : Create Funding Round"
      )

      context.fail!(message: option_pool.funding_round.errors.full_messages) if option_pool.funding_round.id.blank?

    else
      Rails.logger.error "No OptionPool specified"
      context.fail!(message: "No OptionPool specified")
    end
  end

  def create_audit_trail(option_pool)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :setup_funding_round, owner: "FundingRound", quantity: option_pool.number_of_options, operation: :create_record, ref: option_pool.funding_round, entity_id: option_pool.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.option_pool)
  end
end
