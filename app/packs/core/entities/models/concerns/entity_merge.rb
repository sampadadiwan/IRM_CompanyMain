module EntityMerge
  extend ActiveSupport::Concern

  included do
    def self.merge(old_entity, new_entity)
      old_entity.investors.update_all(entity_id: new_entity.id)
      Investor.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)
      Investor.where(entity_id: old_entity.id).update_all(entity_id: new_entity.id)

      old_entity.option_pools.update_all(entity_id: new_entity.id)
      old_entity.excercises.update_all(entity_id: new_entity.id)

      Entity.where(parent_entity_id: old_entity.id).update_all(parent_entity_id: new_entity.id)

      old_entity.funding_rounds.update_all(entity_id: new_entity.id)
      old_entity.valuations.update_all(entity_id: new_entity.id)
      old_entity.holdings.update_all(entity_id: new_entity.id)

      old_entity.investments.update_all(entity_id: new_entity.id)
      old_entity.aggregate_investments.update_all(entity_id: new_entity.id)

      old_entity.exchange_rates.update_all(entity_id: new_entity.id)
      old_entity.fees.update_all(entity_id: new_entity.id)
      old_entity.import_uploads.update_all(entity_id: new_entity.id)

      merge_misc(old_entity, new_entity)
      merge_access(old_entity, new_entity)
      merge_fund_data(old_entity, new_entity)
      merge_secondary_sale(old_entity, new_entity)
      merge_deal(old_entity, new_entity)
      merge_notices(old_entity, new_entity)
    end

    def self.merge_notices(old_entity, new_entity)
      InvestorNoticeEntry.where(entity_id: old_entity.id, investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)
    end

    def self.merge_misc(old_entity, new_entity)
      old_entity.notes.update_all(entity_id: new_entity.id)
      old_entity.employees.update_all(entity_id: new_entity.id)
      old_entity.documents.update_all(entity_id: new_entity.id)
      old_entity.folders.update_all(entity_id: new_entity.id)
      old_entity.messages.update_all(entity_id: new_entity.id)
      old_entity.tasks.update_all(entity_id: new_entity.id)
      Task.where(for_entity_id: old_entity.id).update_all(for_entity_id: new_entity.id)
      # old_entity.esigns.update_all(entity_id: new_entity.id)

      old_entity.investor_kycs.update_all(entity_id: new_entity.id)
      old_entity.approvals.update_all(entity_id: new_entity.id)
      old_entity.approval_responses.update_all(entity_id: new_entity.id)
      ApprovalResponse.where(response_entity_id: old_entity.id).update_all(response_entity_id: new_entity.id)
    end

    def self.merge_access(old_entity, new_entity)
      old_entity.investor_advisors.update_all(entity_id: new_entity.id)
      old_entity.investor_accesses.update_all(entity_id: new_entity.id)
      InvestorAccess.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)
      old_entity.access_rights.update_all(entity_id: new_entity.id)
      # AccessRight.where(access_to_investor_id: old_investor.id).update_all(access_to_investor_id: new_investor.id)
    end

    def self.merge_deal(old_entity, new_entity)
      old_entity.deals.update_all(entity_id: new_entity.id)
      old_entity.deal_activities.update_all(entity_id: new_entity.id)
      old_entity.deal_investors.update_all(entity_id: new_entity.id)
      DealInvestor.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)
    end

    def self.merge_secondary_sale(old_entity, new_entity)
      old_entity.secondary_sales.update_all(entity_id: new_entity.id)
      old_entity.interests_shown.update_all(entity_id: new_entity.id)
      Interest.where(interest_entity_id: old_entity.id).update_all(interest_entity_id: new_entity.id)
      old_entity.offers.update_all(entity_id: new_entity.id)
    end

    def self.merge_fund_data(old_entity, new_entity)
      old_entity.funds.update_all(entity_id: new_entity.id)
      old_entity.fund_reports.update_all(entity_id: new_entity.id)
      old_entity.capital_calls.update_all(entity_id: new_entity.id)
      old_entity.capital_commitments.update_all(entity_id: new_entity.id)
      old_entity.commitment_adjustments.update_all(entity_id: new_entity.id)
      old_entity.capital_remittances.update_all(entity_id: new_entity.id)
      old_entity.capital_remittance_payments.update_all(entity_id: new_entity.id)
      old_entity.capital_distributions.update_all(entity_id: new_entity.id)
      old_entity.capital_distribution_payments.update_all(entity_id: new_entity.id)
      old_entity.fund_formulas.update_all(entity_id: new_entity.id)
      old_entity.fund_units.update_all(entity_id: new_entity.id)
      old_entity.fund_ratios.update_all(entity_id: new_entity.id)

      old_entity.portfolio_investments.update_all(entity_id: new_entity.id)
      old_entity.aggregate_portfolio_investments.update_all(entity_id: new_entity.id)

      old_entity.investment_opportunities.update_all(entity_id: new_entity.id)
      old_entity.expression_of_interests.update_all(entity_id: new_entity.id)
      ExpressionOfInterest.where(eoi_entity_id: old_entity.id).update_all(eoi_entity_id: new_entity.id)
    end
  end
end
