module AccountEntryAllocation
  ############################################################
  # 7. GeneratePortfolioNumbersForFund Operation
  # This FundFurmla is used to generate portfolio company values for a fund
  # Ex FMV for the portfolio company in this fund on this date
  ############################################################
  class GeneratePortfolioNumbersForFund < AllocationBaseOperation
    DEFAULT_FEILDS = { "Bought Amount" => :bought_amount_cents, "Cost Of Remaining" => :cost_of_remaining_cents, "Cost Of Sold" => :cost_of_sold_cents, "Sold Amount" => :sold_amount_cents, "FMV" => :fmv_cents, "Realized Gain" => :gain_cents, "Unrealized Gain" => :unrealized_gain_cents }.freeze

    step :allocate_portfolios_company

    def allocate_portfolios_company(ctx, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula = ctx[:fund_formula]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      user_id      = ctx[:user_id]

      Rails.logger.debug { "GeneratePortfolioNumbersForFund(#{fund_formula.name})" }

      portfolio_companies = fund.entity.investors.joins(:portfolio_investments)
                                .where(portfolio_investments: { fund_id: fund.id })
                                .where(portfolio_investments: { investment_date: ..end_date })
                                .distinct

      # We create account_entries for each of the following fields
      fields = begin
        field_map(fund_formula)
      rescue StandardError
        # A formula that is not a usable field map (or is refused) falls back to the default fields,
        # as before: safe_eval!'s UnsafeEvalError and FormulaSandbox::Rejected are StandardErrors
        DEFAULT_FEILDS
      end

      fields = DEFAULT_FEILDS if fields.keys.blank?

      portfolio_companies.each_with_index do |portfolio_company, idx|
        begin
          aggregate_portfolio_investment = portfolio_company.aggregate_portfolio_investment(fund_id: fund.id, as_of: end_date)

          create_instance_variables(ctx)

          fields.each do |name, field|
            fund_formula.name = name
            fund_formula.formula = "aggregate_portfolio_investment.#{field}"

            ae = AccountEntrySqlite.new(
              name: fund_formula.name,
              entry_type: fund_formula.entry_type,
              entity_id: fund.entity_id,
              fund_id: fund.id,
              parent_type: portfolio_company.class.name,
              parent_id: portfolio_company.id,
              parent_name: portfolio_company.to_s[0..254],
              parent: portfolio_company,
              reporting_date: end_date,
              period: "As of #{end_date}",
              generated: true,
              cumulative: true,
              fund_formula_id: fund_formula.id
            )

            AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: nil, parent: portfolio_company, bdg: binding))
          end
        rescue StandardError => e
          raise "Error in #{fund_formula.name}:#{fund_formula.id} for #{fund}: #{e.message}"
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end

    # The fields an AggregatePortfolioInvestment may be read through ("aggregate_portfolio_investment.#{field}"
    # becomes a formula below): the defaults, which are the API's money and quantity readers
    ALLOWED_FIELDS = DEFAULT_FEILDS.values.freeze

    # C2 — the formula is a {"Entry name" => :field} hash literal. It is read with RubyLiteral (parse
    # only, nothing runs), which gives exactly the hash eval gave for every literal map. Only a text
    # that is not a plain literal goes on to the mode: off evaluates it as before (behind safe_eval!),
    # log logs and evaluates it, enforce refuses it. A field outside ALLOWED_FIELDS is logged in log
    # mode and refused in enforce mode.
    def field_map(fund_formula)
      context = "FundFormula##{fund_formula.id}"
      fields = begin
        RubyLiteral.parse_hash(fund_formula.formula)
      rescue RubyLiteral::NotLiteral => e
        literal_fallback(fund_formula.formula, context, e)
      end

      # Every field name must be one the aggregate exposes for this rule (log / enforce)
      unknown = fields.values.map { |field| field.to_s.to_sym }.reject { |field| ALLOWED_FIELDS.include?(field) }
      if unknown.any? && FormulaSandbox.mode != "off"
        message = "[formula_sandbox] #{FormulaSandbox.mode == 'enforce' ? 'rejected' : 'would_reject'} profile=portfolio_numbers context=#{context} reasons=unknown fields #{unknown.join(', ')}"
        Rails.logger.warn(message)
        raise FormulaSandbox::Rejected, "Refusing fields #{unknown.join(', ')} (#{context})" if FormulaSandbox.mode == "enforce"
      end
      fields
    end

    # A field map that is not a plain literal: today's evaluation in off / log mode, refused in enforce
    def literal_fallback(formula, context, error)
      raise FormulaSandbox::Rejected, "Refusing a field map that is not a plain hash (#{context}): #{error.message}" if FormulaSandbox.mode == "enforce"

      Rails.logger.warn("[formula_sandbox] would_reject profile=portfolio_numbers context=#{context} reasons=#{error.message}") if FormulaSandbox.mode == "log"
      eval(ApplicationRecord.safe_eval!(formula, context:)) # rubocop:disable Security/Eval
    end
  end
end
