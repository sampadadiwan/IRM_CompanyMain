module AccountEntryAllocation
  ############################################################
  # 3. BulkInsertData Operation
  ############################################################
  class BulkInsertData < AllocationBaseOperation
    step :bulk_insert_data

    def bulk_insert_data(ctx, rollup_name:, rollup_entry_type:, **)
      Rails.logger.debug { "bulk_insert_data: #{ctx}, #{rollup_name}, #{rollup_entry_type}" }

      fund          = ctx[:fund]
      fund_formula  = ctx[:fund_formula]
      allocation_run_id = ctx[:allocation_run_id]
      ctx[:commitment_cache]

      bulk_records = ctx[:bulk_insert_records] || []
      records_in_allocation_by_formula = fund.account_entries.generated.where(allocation_run_id:, fund_formula_id: fund_formula.id)

      if bulk_records.present?
        # Insert the bulk records in batches
        # inserting all at once exceeds the max_allowed_packet of 64 mb and gives the error - Mysql2::Error::ConnectionError: Got a packet bigger than 'max_allowed_packet' bytes
        # 10k AE records is around 12.5mb which avoids the error
        bulk_records.each_slice(10_000) do |batch|
          AccountEntry.insert_all(batch)
        end

        # Calculate the number of existing records
        total_record_count   = records_in_allocation_by_formula.count
        # Calculate the number of inserted records
        inserted_row_count   = total_record_count
        # Log the number of inserted records
        Rails.logger.debug { "#{fund_formula.name}: Inserted #{inserted_row_count} of #{bulk_records.length} records, total: #{total_record_count}" }
        # Raise an error if the number of inserted records does not match the expected count
        raise "Inserts failed" if inserted_row_count != bulk_records.length
      else
        Rails.logger.debug { "#{fund_formula.name}: No records to insert" }
      end

      # Roll up the account entries if needed
      if fund_formula.roll_up
        existing_record_count = records_in_allocation_by_formula.count
        # Reset the array for new bulk insert records
        ctx[:bulk_insert_cumulative_records] = []

        # Iterate over each commitment and generate cumulative account entries
        fund_formula.commitments(ctx[:end_date], ctx[:sample]).each_with_index do |capital_commitment, _idx|
          generate_cumulative_ae(ctx, capital_commitment, rollup_name, rollup_entry_type)
        end

        # Insert the bulk records if present
        if ctx[:bulk_insert_cumulative_records].present?
          AccountEntry.insert_all(ctx[:bulk_insert_cumulative_records])

          new_record_count = records_in_allocation_by_formula.count
          # Calculate the number of inserted records ( -1 cause the cumulative_ae is already in the account_entries)
          rollup_inserted_row_count = new_record_count - existing_record_count

          # Calculate the expected number of inserted records
          bulk_insert_cumulative_records_length = ctx[:bulk_insert_cumulative_records].length
          Rails.logger.debug { "#{fund_formula.name}: Inserted #{rollup_inserted_row_count} roll_up records, expected #{bulk_insert_cumulative_records_length}" }

          # Raise an error if the number of inserted records does not match the expected count
          raise "Rollup inserts failed inserted #{rollup_inserted_row_count}, expected #{bulk_insert_cumulative_records_length} " if rollup_inserted_row_count != bulk_insert_cumulative_records_length
        else
          Rails.logger.debug { "#{fund_formula.name}: No roll_up records to insert" }
        end
      end

      # For "GenerateAccountEntry" rule_type, we need to rollup the generated entries to the fund level
      if ["GenerateAccountEntry"].include? fund_formula.rule_type
        ctx[:bulk_insert_records] = []
        AccountEntryAllocation::RollupAsFundAccountEntry.call(ctx)
      end

      true
    end

    def generate_cumulative_ae(ctx, capital_commitment, rollup_name, rollup_entry_type)
      commitment_cache = ctx[:commitment_cache]

      # Generate the cumulative account entry for the capital commitment
      cumulative_ae = capital_commitment.rollup_account_entries(rollup_name, rollup_entry_type, ctx[:start_date], ctx[:end_date])
      cumulative_ae.allocation_run_id = ctx[:allocation_run_id]
      cumulative_ae.fund_formula_id = ctx[:fund_formula].id

      # Add the attributes of the cumulative account entry to the bulk insert records, excluding certain fields
      ctx[:bulk_insert_cumulative_records] << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")

      # Update the commitment cache with the computed fields
      commitment_cache.add_to_computed_fields_cache(ctx, capital_commitment, cumulative_ae)
    end
  end
end
