# Links from an allocation run checker report to the account entries behind it.
#
# A report that says "Setup Fee is out by 599" is only half an answer — the other half is the
# entries themselves, so every finding that names an entry or a folio links straight through to
# the account entries screen, pre-filtered.
module AllocationRunReportsHelper
  # Every account entry this run produced, filtered by the run itself. Exactly the same link the
  # allocation screen already offers on each row (allocate_form.html.erb), so both places lead
  # to the same list.
  #
  # Runs made before the engine began stamping allocation_run_id on entries (see
  # AllocationRunReportBuild::ENTRY_TAGGING_STARTED_ON) have no tagged entries, so this link
  # comes back empty for them — the same as the allocation screen's own link, which is why that
  # screen only shows it for runs after that date.
  #
  # @param allocation_run [AllocationRun]
  # @return [String] path to the filtered account entries screen
  def run_account_entries_path(allocation_run)
    conditions = [["allocation_run_id", :eq, allocation_run.id],
                  ["reporting_date", :eq, allocation_run.end_date.to_fs(:db)]]

    account_entries_path(filter: true, fund_id: allocation_run.fund_id,
                         q: ransack_query_params_multiple(conditions))
  end

  # The entries behind one row of one finding. `conditions` comes straight out of the report's
  # json_fields as [field, predicate, value] triples — see AllocationRunReportBuild's drill-down
  # filter builders, which is where the window for each check is decided.
  #
  # @param allocation_run [AllocationRun]
  # @param conditions [Array<Array>, nil]
  # @return [String, nil] nil when the finding row has nothing to drill into
  def finding_entries_path(allocation_run, conditions)
    return nil if conditions.blank?

    account_entries_path(filter: true, fund_id: allocation_run.fund_id,
                         q: ransack_query_params_multiple(conditions))
  end
end
