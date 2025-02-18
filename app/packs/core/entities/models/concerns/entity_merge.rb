module EntityMerge
  extend ActiveSupport::Concern

  included do
    # Used to merge two entities, which are of entity_type Investor
    def self.merge_investor_entity(defunct_entity, retained_entity)
      Investor.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)
      InvestorAccess.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)
      User.where(entity_id: defunct_entity.id).update_all(entity_id: retained_entity.id)
      defunct_entity.update_columns(name: "#{defunct_entity.name} (Defunct)")
    end

    # This should NEVER be called ever, it is a dangerous method
    # Only call it if you are sure about what you are doing
    # See if you can use merge_investor_entity instead
    def self.merge_entity(defunct_entity, retained_entity)
      # Copy over investors
      Investor.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)

      Investor.where(entity_id: defunct_entity.id).find_each do |old_investor|
        new_investor = retained_entity.investors.where(investor_entity_id: old_investor.investor_entity_id).first
        if new_investor.present?
          # We have this investor, so merge
          Investor.merge(old_investor, new_investor, allow_cross_entity: true)
        else
          # We dont have this investor, so just update entity id
          old_inv.update_column(:entity_id, retained_entity.id)
        end
      end

      # TODO: This is not correct, we need to merge the Trust and Employee entities
      # Entity.where(parent_entity_id: defunct_entity.id).update_all(parent_entity_id: retained_entity.id)

      defunct_entity.valuations.update_all(entity_id: retained_entity.id)

      defunct_entity.investments.update_all(entity_id: retained_entity.id)

      defunct_entity.exchange_rates.update_all(entity_id: retained_entity.id)
      defunct_entity.fees.update_all(entity_id: retained_entity.id)
      defunct_entity.import_uploads.update_all(entity_id: retained_entity.id)

      merge_notices(defunct_entity, retained_entity)

      merge_misc(defunct_entity, retained_entity)
      merge_access(defunct_entity, retained_entity)
      merge_fund_data(defunct_entity, retained_entity)
      merge_secondary_sale(defunct_entity, retained_entity)
      merge_deal(defunct_entity, retained_entity)

      defunct_entity.employees.update_all(entity_id: retained_entity.id)
      defunct_entity.update_columns(name: "#{defunct_entity.name} (Defunct)")
    end

    # Not used, the following code wont work
    def self.merge_notices(defunct_entity, retained_entity)
      InvestorNoticeEntry.where(entity_id: defunct_entity.id).update_all(entity_id: retained_entity.id)
      InvestorNoticeEntry.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)
    end

    def self.merge_misc(defunct_entity, retained_entity)
      defunct_entity.notes.update_all(entity_id: retained_entity.id)
      defunct_entity.employees.update_all(entity_id: retained_entity.id)
      defunct_entity.documents.update_all(entity_id: retained_entity.id)
      defunct_entity.folders.update_all(entity_id: retained_entity.id)
      defunct_entity.messages.update_all(entity_id: retained_entity.id)
      defunct_entity.tasks.update_all(entity_id: retained_entity.id)
      Task.where(for_entity_id: defunct_entity.id).update_all(for_entity_id: retained_entity.id)

      defunct_entity.investor_kycs.update_all(entity_id: retained_entity.id)
      defunct_entity.approvals.update_all(entity_id: retained_entity.id)
      defunct_entity.approval_responses.update_all(entity_id: retained_entity.id)
      ApprovalResponse.where(response_entity_id: defunct_entity.id).update_all(response_entity_id: retained_entity.id)

      defunct_entity.kpi_reports.update_all(entity_id: retained_entity.id)
      defunct_entity.kpis.update_all(entity_id: retained_entity.id)
      defunct_entity.investor_kpi_mappings.update_all(entity_id: retained_entity.id)
    end

    def self.merge_access(defunct_entity, retained_entity)
      defunct_entity.investor_advisors.update_all(entity_id: retained_entity.id)
      defunct_entity.investor_accesses.update_all(entity_id: retained_entity.id)
      InvestorAccess.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)
      defunct_entity.access_rights.update_all(entity_id: retained_entity.id)
      AccessRight.where(entity_id: defunct_entity.id).update_all(entity_id: retained_entity.id)
    end

    def self.merge_deal(defunct_entity, retained_entity)
      defunct_entity.deals.update_all(entity_id: retained_entity.id)
      defunct_entity.deal_activities.update_all(entity_id: retained_entity.id)
      defunct_entity.deal_investors.update_all(entity_id: retained_entity.id)
      DealInvestor.where(investor_entity_id: defunct_entity.id).update_all(investor_entity_id: retained_entity.id)
    end

    def self.merge_secondary_sale(defunct_entity, retained_entity)
      defunct_entity.secondary_sales.update_all(entity_id: retained_entity.id)
      defunct_entity.interests_shown.update_all(entity_id: retained_entity.id)
      Interest.where(interest_entity_id: defunct_entity.id).update_all(interest_entity_id: retained_entity.id)
      defunct_entity.offers.update_all(entity_id: retained_entity.id)
    end

    def self.merge_fund_data(defunct_entity, retained_entity)
      defunct_entity.funds.update_all(entity_id: retained_entity.id)
      defunct_entity.fund_reports.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_calls.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_commitments.update_all(entity_id: retained_entity.id)
      defunct_entity.commitment_adjustments.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_remittances.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_remittance_payments.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_distributions.update_all(entity_id: retained_entity.id)
      defunct_entity.capital_distribution_payments.update_all(entity_id: retained_entity.id)
      defunct_entity.fund_formulas.update_all(entity_id: retained_entity.id)
      defunct_entity.fund_units.update_all(entity_id: retained_entity.id)
      defunct_entity.fund_ratios.update_all(entity_id: retained_entity.id)

      defunct_entity.portfolio_investments.update_all(entity_id: retained_entity.id)
      defunct_entity.aggregate_portfolio_investments.update_all(entity_id: retained_entity.id)
      defunct_entity.investment_instruments.update_all(entity_id: retained_entity.id)
      defunct_entity.portfolio_cashflows.update_all(entity_id: retained_entity.id)

      defunct_entity.investment_opportunities.update_all(entity_id: retained_entity.id)
      defunct_entity.expression_of_interests.update_all(entity_id: retained_entity.id)
      ExpressionOfInterest.where(eoi_entity_id: defunct_entity.id).update_all(eoi_entity_id: retained_entity.id)
    end
  end
end
