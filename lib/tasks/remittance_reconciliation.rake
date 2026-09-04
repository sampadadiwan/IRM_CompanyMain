# frozen_string_literal: true

namespace :remittance_reconciliation do
  desc "Generate a bank statement xlsx for an existing capital call, in one bank's export format (icici or " \
       "axis), from the call's own remittances — crafted so RemittanceReconciliationAgent produces every " \
       "outcome (Exact, Partial, Probable, discrepancy, overpayment, No match, Internal, ignored withdrawal). " \
       "Creates nothing in the DB. Add 'run' as the third argument to also run the agent against the call. " \
       "Usage: rake \"remittance_reconciliation:statement[<capital_call_id>,icici]\" or " \
       "rake \"remittance_reconciliation:statement[<capital_call_id>,axis,run]\""
  task :statement, %i[capital_call_id bank run] => :environment do |_t, args|
    require Rails.root.join("lib/remittance_reconciliation_statement_generator")

    abort "Usage: rake \"remittance_reconciliation:statement[<capital_call_id>,<icici|axis>,run]\"" if args[:capital_call_id].blank?

    RemittanceReconciliationStatementGenerator.new(args[:capital_call_id], bank: args[:bank].presence || "icici",
                                                                           run_agent: args[:run].to_s == "run").call
  end
end
