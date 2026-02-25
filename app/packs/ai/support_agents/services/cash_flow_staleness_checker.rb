# frozen_string_literal: true

# Shared staleness checking logic used by both:
# - CashFlowAssistantAgent (staleness gate before calculation)
# - CashFlowStalenessReminderService (daily reminder emails)

class CashFlowStalenessChecker
  def initialize(support_agent)
    @config = support_agent.json_fields
    @cash_tags = (@config["cash_tags"] || "").split(",").map(&:strip).compact_blank
  end

  # Checks all configured funds and returns array of fund status hashes.
  #
  # @return [Array<Hash>] each with :fund_id, :name, :status, :block_reasons, :last_cash_update
  def check_all_funds
    funds_config = @config["funds"] || []
    funds_config.filter_map { |fc| check_fund(fc) }
  end

  # Checks a single fund's data freshness.
  #
  # @param fund_config [Hash] from agent_config["funds"] array
  # @return [Hash, nil] fund status hash or nil if fund not found
  def check_fund(fund_config)
    fund = Fund.find_by(id: fund_config["fund_id"])
    return nil unless fund

    thresholds   = fund_config["staleness_thresholds"] || {}
    cash_max     = (thresholds["cash_accounts_max_days"] || 30).to_i
    proforma_max = (thresholds["proforma_max_days"] || 90).to_i
    entities     = fund_entities(fund)

    result = {
      fund_id: fund.id, name: fund_config["name"] || fund.name,
      status: "ready", block_reasons: []
    }

    check_cash_staleness(fund, entities, cash_max, result)
    check_proforma_staleness(fund, entities, proforma_max, result)

    result[:last_cash_update] = latest_cash_date(fund, entities)
    result
  end

  private

  def fund_entities(fund)
    [fund.entity] + fund.entity.children.to_a
  end

  def check_cash_staleness(fund, entities, max_days, result)
    entities.each do |entity|
      latest_cash = AccountEntry
                    .where(fund_id: fund.id, entity_id: entity.id)
                    .fund_entries
                    .where(entry_type: @cash_tags)
                    .order(reporting_date: :desc)
                    .first

      if latest_cash.nil?
        result[:status] = "blocked"
        result[:block_reasons] << "No cash data for #{entity.name}"
      elsif (cash_age = (Time.zone.today - latest_cash.reporting_date).to_i) > max_days
        result[:status] = "blocked"
        result[:block_reasons] << "#{entity.name}: Cash #{cash_age}d old (max #{max_days}d)"
      end
    end
  end

  def check_proforma_staleness(fund, entities, max_days, result)
    entities.each do |entity|
      PortfolioInvestment.proforma
                         .where(fund_id: fund.id, entity_id: entity.id)
                         .where("amount_cents > 0")
                         .where(created_at: ...max_days.days.ago)
                         .find_each do |pi|
                           age = (Time.zone.today - pi.created_at.to_date).to_i
                           result[:status] = "blocked"
                           result[:block_reasons] << "#{entity.name}: Proforma '#{pi.portfolio_company_name}' #{age}d old (max #{max_days}d)"
                         end
    end
  end

  def latest_cash_date(fund, entities)
    AccountEntry
      .where(fund_id: fund.id, entity_id: entities.map(&:id))
      .fund_entries
      .where(entry_type: @cash_tags)
      .maximum(:reporting_date)
  end
end
