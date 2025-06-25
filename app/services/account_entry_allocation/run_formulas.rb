module AccountEntryAllocation
  ############################################################
  # 1. RunFormulas Operation
  ############################################################
  class RunFormulas < AllocationBaseOperation
    include Rails.application.routes.url_helpers
    include ApplicationHelper

    step :run_formulas
    step :generate_fund_ratios
    step :generate_soa

    def run_formulas(ctx, **)
      if ctx[:run_allocations]

        fund                 = ctx[:fund]
        rule_for             = ctx[:rule_for]
        tag_list             = ctx[:tag_list]
        user_id              = ctx[:user_id]
        allocation_run       = ctx[:allocation_run]
        start_date           = ctx[:start_date]
        end_date             = ctx[:end_date]
        run_start_time       = Time.zone.now

        # Used to update the created account_entries. See CreateAccountEntry
        ctx[:form_type_id]   = fund.entity.form_types.where(name: "AccountEntry").last
        ctx[:bulk_insert_records] = []

        # Get the enabled formulas
        formulas = FundFormula.enabled.where(fund_id: fund.id).order(sequence: :asc).includes(:fund, :entity)
        # Run only the formulas with the specified rule_for
        formulas = formulas.where(rule_for: rule_for) if rule_for.present?
        # Run only the formulas with the specified tags
        formulas = formulas.with_tags(tag_list.split(",")) if tag_list.present?
        formula_ids = formulas.pluck(:id)

        fund_account_entries = fund.account_entries.generated.where(reporting_date: start_date..end_date)
        # Delete existing fund account entries for the formulas
        fund_account_entries = fund_account_entries.where(fund_formula_id: formula_ids)

        batch_size = 20_000
        count = fund_account_entries.count
        idx = 1
        loop do
          Rails.logger.debug { "Deleting batch #{idx} of fund account entries: #{count}" }
          deleted = fund_account_entries.limit(batch_size).delete_all
          break if deleted.zero?

          sleep(0.1) # Small pause to reduce contention
          idx += 1
        end

        # Ensure that the portfolio_investments are up to date before running formulas. As this may compute the expenses for the portfolio investments
        fund.resave_portfolio_investments

        ctx[:formula_count] = formulas.count

        formulas.each_with_index do |fund_formula, index|
          ctx[:formula_index] = index
          start_time = Time.zone.now

          # Call sub-operation to run the formula
          # We re-use the same ctx for sub-ops, but add the current fund_formula:
          sub_ctx = ctx.merge(fund_formula: fund_formula)
          result = AccountEntryAllocation::RunFormula.call(sub_ctx)
          if result.failure? && result[:error].present?
            # If there's an error, log/raise as needed
            # The sub-operation might raise an error, or we can handle it here
            raise result[:error]
          end

          # Update execution_time
          fund_formula.update_column(:execution_time, ((Time.zone.now - start_time) * 1000).to_i)

          # Provide notification
          notify("Completed #{index + 1} of #{ctx[:formula_count]}: #{fund_formula.name}", :success, user_id)
        rescue StandardError => e
          error_message = "Error in Formula #{fund_formula.sequence}: #{fund_formula.name} : #{e.message}"
          notify(error_message, :danger, user_id)
          Rails.logger.debug { error_message }
          allocation_run&.update_column(:status, error_message)
          raise e
        end

        # Display generated links post run
        display_generated_links(ctx, fund:, start_date:, end_date:, user_id:, run_start_time:)

        # If we reach here, all formulas ran successfully
        allocation_run&.update_column(:status, "Success")
      end
      true
    end

    def display_generated_links(ctx, fund:, start_date:, end_date:, user_id:, run_start_time:)
      time_taken = ((Time.zone.now - run_start_time)).to_i
      msg = "Done running #{ctx[:formula_count]} formulas for #{start_date} - #{end_date} in #{time_taken} seconds"

      entry_types = [
        ['', 'View Account Entries'],
        ['Expense', 'View Expenses'],
        ['Portfolio Allocation', 'View Portfolio Allocation']
      ]

      links_html = entry_types.map do |entry_type, label|
        query_params = ransack_query_params_multiple([
                                                       ['allocation_run_id', :eq, ctx[:allocation_run_id]],
                                                       [:entry_type, :eq, entry_type]
                                                     ])
        ActionController::Base.helpers.link_to(label, account_entries_path(fund_id: fund.id, filter: true, q: query_params), class: 'mb-1 badge  bg-primary-subtle text-primary', target: '_blank', rel: 'noopener')
      end.join

      notify("#{msg}<br>#{links_html}", :success, user_id)
    end

    # rubocop:disable Lint/RescueException
    def generate_fund_ratios(ctx, fund:, start_date:, end_date:, user_id:, **)
      if ctx[:fund_ratios]
        begin
          FundRatiosJob.perform_now(fund.id, nil, end_date, user_id, true)
          msg = "Done generating fund ratios for #{start_date} - #{end_date}"
          Rails.logger.info msg
          notify(msg, :success, user_id)
          true
        rescue Exception => e
          Rails.logger.error e.backtrace
          msg = "Error generating fund ratios for #{start_date} - #{end_date}: #{e.message}"
          Rails.logger.error msg
          notify(msg, :danger, user_id)
          false
        end
      else
        Rails.logger.info "Skipping fund ratios generation"
        true
      end
    end
    # rubocop:enable Lint/RescueException

    # rubocop:disable Lint/RescueException
    def generate_soa(ctx, fund:, start_date:, end_date:, user_id:, template_id:, **)
      if ctx[:generate_soa]
        begin
          CapitalCommitmentSoaJob.perform_later(fund.id, nil, start_date.to_s, end_date.to_s, user_id, template_id:)
          msg = "Done generating SOA for #{start_date} - #{end_date}"
          Rails.logger.info msg
          notify(msg, :success, user_id)
          true
        rescue Exception => e
          Rails.logger.error e.backtrace
          msg = "Error generating SOA for #{start_date} - #{end_date}: #{e.message}"
          Rails.logger.error msg
          notify(msg, :danger, user_id)
          false
        end
      else
        Rails.logger.info "Skipping SOA generation"
        true
      end
    end
    # rubocop:enable Lint/RescueException
  end
end
