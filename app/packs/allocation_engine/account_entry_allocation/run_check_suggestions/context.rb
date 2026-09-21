module AccountEntryAllocation
  module RunCheckSuggestions
    # Everything the suggestion rules read about a fund, loaded once. account_entries is only ever
    # aggregated: one DISTINCT over the fund's uploaded rows, never the rows themselves.
    class Context
      attr_reader :fund

      def initialize(fund)
        @fund = fund
      end

      # The enabled formulas that compute entries, in sequence order: what an allocation run executes
      # (RunFormulas reads FundFormula.enabled). A disabled formula's reads are no reason for a check.
      def formulas
        @formulas ||= fund.fund_formulas.without_run_checks.enabled.order(:sequence).to_a
      end

      def existing_checks
        @existing_checks ||= fund.fund_formulas.run_checks.order(:sequence).to_a
      end

      # [{name:, entry_type:, parent_type:, fund_level:}] for every distinct combination ever uploaded
      def uploaded
        @uploaded ||= AccountEntry.where(fund_id: fund.id, generated: false, deleted_at: nil)
                                  .distinct
                                  .pluck(:name, :entry_type, :parent_type, Arel.sql("CASE WHEN account_entries.capital_commitment_id IS NULL THEN 1 ELSE 0 END"))
                                  .map { |name, entry_type, parent_type, fund_level| { name:, entry_type:, parent_type:, fund_level: fund_level.to_i == 1 } }
      end

      # { json key => label } of the entity's custom fields for a model ("AccountEntry", "PortfolioInvestment")
      def custom_field_labels(model_name)
        @custom_field_labels ||= {}
        @custom_field_labels[model_name] ||= FormCustomField.joins(:form_type)
                                                            .where(form_types: { entity_id: fund.entity_id, name: model_name })
                                                            .pluck(:name, :label).to_h
      end

      # { unit type => folio count }
      def unit_types
        @unit_types ||= fund.capital_commitments.group(:unit_type).count
      end

      def unit_setting_columns
        FundUnitSetting.column_names
      end

      def portfolio_investments?
        return @portfolio_investments if defined?(@portfolio_investments)

        @portfolio_investments = PortfolioInvestment.include_proforma.exists?(fund_id: fund.id)
      end

      def incremental?
        CommitmentAccountEntry.incremental_since_inception?(fund)
      end

      # { [from, to] => [what needs it] } for every rate the fund needs; empty when it needs none
      def fx_rate_sources
        @fx_rate_sources ||= AllocationRunReadiness.new(fund:, entity_id: fund.entity_id, end_date: Time.zone.today, n_days: 0).fx_rate_sources
      end

      def last_successful_run
        @last_successful_run ||= fund.allocation_runs.successful.order(end_date: :desc, id: :desc).first
      end
    end
  end
end
