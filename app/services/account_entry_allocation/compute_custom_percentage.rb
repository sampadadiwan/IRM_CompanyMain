module AccountEntryAllocation
  ############################################################
  # 5. ComputeCustomPercentage Operation
  ############################################################
  class ComputeCustomPercentage < AllocationBaseOperation
    step :compute_custom_percentage

    def compute_custom_percentage(ctx, **)
      fund          = ctx[:fund]
      end_date      = ctx[:end_date]
      sample        = ctx[:sample]
      user_id       = ctx[:user_id]
      fund_formula  = ctx[:fund_formula]
      commitment_cache = ctx[:commitment_cache]

      field_name = fund_formula.name.gsub("Percentage", "").strip
      total = 0
      count = 0
      cc_map = {}

      # First pass, gather sums
      fund_formula.commitments(end_date, sample).includes(:entity, :fund).find_each do |capital_commitment|
        # Get the last entry for the field_name before the end_date
        # This example might break if there's no record. Check for nil in a real app.
        last_ae = capital_commitment.account_entries
                                    .where(name: field_name, reporting_date: ..end_date)
                                    .order(reporting_date: :asc).last
        amount_cents = last_ae&.amount_cents.to_i

        cc_map[capital_commitment.id] = {
          "amount_cents" => amount_cents,
          "entry_type" => "Percentage"
        }
        total += amount_cents
        count += 1
      end

      # Delete all previously generated percentages
      AccountEntry.where(
        name: "#{field_name} Percentage",
        entity_id: fund.entity_id,
        fund: fund,
        reporting_date: end_date,
        generated: true
      ).find_each(&:destroy)

      # Second pass, create new entries
      bulk_records = []
      fund_formula.commitments(end_date, sample).includes(:entity, :fund).each_with_index do |capital_commitment, idx|
        Rails.logger.debug { "ComputeCustomPercentage: #{field_name} Percentage, #{capital_commitment.id}, #{cc_map[capital_commitment.id]['amount_cents']} / #{total} = #{(100.0 * cc_map[capital_commitment.id]['amount_cents'] / total).round(2)}" } if total.positive?

        percentage = total.positive? ? (100.0 * cc_map[capital_commitment.id]["amount_cents"] / total) : 0
        account_entry = AccountEntry.new(
          name: "#{field_name} Percentage",
          entry_type: cc_map[capital_commitment.id]["entry_type"],
          entity_id: fund.entity_id,
          fund: fund,
          reporting_date: end_date,
          period: "As of #{end_date}",
          capital_commitment: capital_commitment,
          folio_id: capital_commitment.folio_id,
          generated: true,
          amount_cents: percentage,
          cumulative: false,
          fund_formula: fund_formula
        )

        begin
          create_instance_variables(ctx)
          AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry:, capital_commitment: capital_commitment, parent: nil, bdg: binding))
        rescue StandardError => e
          raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
        end

        # end

        # printer = RubyProf::CallStackPrinter.new(result)
        # File.open("tmp/ruby_prof_callstack_#{Time.zone.now}.html", "w") do |file|
        #   printer.print(file)
        # end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end
      true
    end
  end
end
