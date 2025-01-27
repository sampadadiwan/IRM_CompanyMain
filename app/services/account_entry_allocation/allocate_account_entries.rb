module AccountEntryAllocation
  ############################################################
  # 13. AllocateAccountEntries Operation
  ############################################################
  class AllocateAccountEntries < AllocationBaseOperation
    step :allocate_account_entries

    def allocate_account_entries(ctx, name_or_entry_type:, **)
      fund         = ctx[:fund]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      fund_formula = ctx[:fund_formula]

      Rails.logger.debug { "allocate_account_entries #{fund_formula.name}" }

      account_entries = fund.fund_account_entries.where(reporting_date: start_date..end_date)
                            .where(commitment_type: fund_formula.commitment_type)

      account_entries = if name_or_entry_type == "name"
                          account_entries.where(name: fund_formula.name)
                        else
                          account_entries.where(entry_type: fund_formula.name)
                        end

      if account_entries.present?
        account_entries.each do |fund_account_entry|
          Rails.logger.debug { "allocate_account_entries: Allocating #{fund_account_entry}" }
          sub_ctx = ctx.merge(fund_account_entry: fund_account_entry)
          AccountEntryAllocation::AllocateEntry.wtf?(sub_ctx)
        end
      else
        Rails.logger.warn "No account entries found to allocate for #{fund_formula.name} in #{fund.name}"
      end

      true
    end
  end
end
