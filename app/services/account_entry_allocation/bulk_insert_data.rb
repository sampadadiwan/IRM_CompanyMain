module AccountEntryAllocation
  ############################################################
  # 3. BulkInsertData Operation
  ############################################################
  class BulkInsertData < AllocationBaseOperation
    step :bulk_insert_data

    def bulk_insert_data(ctx, rollup_name:, rollup_entry_type:, **)
      Rails.logger.debug { "bulk_insert_data: #{rollup_name}, #{rollup_entry_type}" }

      ctx[:fund]
      fund_formula = ctx[:fund_formula]
      ctx[:allocation_run_id]
      ctx[:commitment_cache]

      bulk_records = ctx[:bulk_insert_records] || []

      if bulk_records.present?
        # Insert the bulk records in batches
        # inserting all at once exceeds the max_allowed_packet of 64 mb and gives the error - Mysql2::Error::ConnectionError: Got a packet bigger than 'max_allowed_packet' bytes
        # 10k AE records is around 12.5mb which avoids the error
        bulk_records.each_slice(10_000) do |batch|
          AccountEntrySqlite.insert_all(batch)
        end

        # Calculate the number of inserted records
        # Since we use insert_all without :unique_by or :on_duplicate,
        # any failure (like a constraint violation) will raise an exception in MySQL.
        # Thus, if we reach this point, all records have been successfully inserted.
        inserted_row_count = bulk_records.length

        # Log the number of inserted records
        Rails.logger.debug { "#{fund_formula.name}: Inserted #{inserted_row_count} records" }
      else
        Rails.logger.debug { "#{fund_formula.name}: No records to insert" }
      end

      # Roll up the account entries if needed
      if fund_formula.roll_up
        # Reset the array for new bulk insert records
        ctx[:bulk_insert_cumulative_records] = []

        # Iterate over each commitment and generate cumulative account entries
        ctx[:commitments].each_with_index do |capital_commitment, _idx|
          generate_cumulative_ae(ctx, capital_commitment, rollup_name, rollup_entry_type)
        end

        # Insert the bulk records if present
        if ctx[:bulk_insert_cumulative_records].present?
          AccountEntrySqlite.insert_all(ctx[:bulk_insert_cumulative_records])

          # Calculate the expected number of inserted records
          bulk_insert_cumulative_records_length = ctx[:bulk_insert_cumulative_records].length
          Rails.logger.debug { "#{fund_formula.name}: Inserted #{bulk_insert_cumulative_records_length} roll_up records" }
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
      cumulative_ae = capital_commitment.rollup_account_entries(rollup_name, rollup_entry_type, ctx[:start_date], ctx[:end_date], sqlite: true)
      cumulative_ae.allocation_run_id = ctx[:allocation_run_id]
      cumulative_ae.fund_formula_id = ctx[:fund_formula].id

      # Add the attributes of the cumulative account entry to the bulk insert records, excluding certain fields
      # Optimization: Only include necessary attributes and let DB handle defaults if possible,
      # but sticking to attributes except metadata for safety.
      ctx[:bulk_insert_cumulative_records] << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")

      # Update the commitment cache with the computed fields
      # Note: commitment_cache update might still be slow if it involves DB calls
      commitment_cache.add_to_computed_fields_cache(ctx, capital_commitment, cumulative_ae)
    end
  end
end
