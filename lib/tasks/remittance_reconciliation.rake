# frozen_string_literal: true

namespace :remittance_reconciliation do
  desc "Generate a bank statement xlsx for an existing capital call, in one bank's export format (icici or " \
       "axis), from the call's own remittances — crafted so RemittanceReconciliationAgent produces every " \
       "outcome (Exact, Partial, Probable, discrepancy, overpayment, No match, Internal, ignored withdrawal). " \
       "Coverage 'full' (default) also pays every other outstanding remittance in full; 'sample' is one row " \
       "per outcome only. Creates nothing in the DB. Add 'run' as the last argument to also run the agent. " \
       "Usage: rake \"remittance_reconciliation:statement[<capital_call_id>,icici]\", " \
       "rake \"remittance_reconciliation:statement[<capital_call_id>,axis,sample]\", " \
       "rake \"remittance_reconciliation:statement[<capital_call_id>,icici,full,run]\""
  task :statement, %i[capital_call_id bank coverage run] => :environment do |_t, args|
    require Rails.root.join("lib/remittance_reconciliation_statement_generator")

    abort "Usage: rake \"remittance_reconciliation:statement[<capital_call_id>,<icici|axis>,<sample|full>,run]\"" if args[:capital_call_id].blank?

    # Be forgiving about position: "run" may be given as the third argument when coverage is omitted.
    coverage = args[:coverage].presence || "full"
    run = args[:run].to_s == "run"
    if coverage == "run"
      coverage = "full"
      run = true
    end

    RemittanceReconciliationStatementGenerator.new(args[:capital_call_id], bank: args[:bank].presence || "icici",
                                                                           coverage: coverage, run_agent: run).call
  end
end
