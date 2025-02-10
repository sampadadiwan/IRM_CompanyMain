module CapitalRemittanceCounters
  extend ActiveSupport::Concern

  included do
    # CapitalCall counters
    counter_culture :capital_call, column_name: 'capital_fee_cents',
                                   delta_column: 'capital_fee_cents',
                                   execute_after_commit: true

    counter_culture :capital_call, column_name: 'other_fee_cents',
                                   delta_column: 'other_fee_cents',
                                   execute_after_commit: true

    counter_culture :capital_call, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                   delta_column: 'collected_amount_cents',
                                   column_names: {
                                     ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                   },
                                   execute_after_commit: true

    counter_culture :capital_call, column_name: 'call_amount_cents',
                                   delta_column: 'call_amount_cents',
                                   execute_after_commit: true

    # Fund counters
    counter_culture :fund, column_name: 'capital_fee_cents',
                           delta_column: 'capital_fee_cents',
                           execute_after_commit: true

    counter_culture :fund, column_name: 'other_fee_cents',
                           delta_column: 'other_fee_cents',
                           execute_after_commit: true

    counter_culture :fund, column_name: 'call_amount_cents',
                           delta_column: 'call_amount_cents',
                           execute_after_commit: true

    counter_culture :fund, column_name: 'tracking_call_amount_cents',
                           delta_column: 'tracking_call_amount_cents',
                           execute_after_commit: true

    counter_culture :fund, column_name:
                          proc { |r| r.verified ? 'collected_amount_cents' : nil },
                           delta_column: 'collected_amount_cents',
                           column_names: lambda {
                                           {
                                             CapitalRemittance.verified => :collected_amount_cents
                                           }
                                         },
                           execute_after_commit: true

    counter_culture :fund, column_name:
                           proc { |r| r.verified ? 'tracking_collected_amount_cents' : nil },
                           delta_column: 'tracking_collected_amount_cents',
                           column_names: lambda {
                             {
                               CapitalRemittance.verified => :tracking_collected_amount_cents
                             }
                           },
                           execute_after_commit: true

    # CapitalCommitment counters
    counter_culture :capital_commitment, column_name: 'other_fee_cents',
                                         delta_column: 'other_fee_cents',
                                         execute_after_commit: true

    counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'folio_collected_amount_cents' : nil },
                                         delta_column: 'folio_collected_amount_cents',
                                         column_names: {
                                           ["capital_remittances.verified = ?", true] => 'folio_collected_amount_cents'
                                         },
                                         execute_after_commit: true

    counter_culture :capital_commitment, column_name: 'call_amount_cents',
                                         delta_column: 'call_amount_cents',
                                         execute_after_commit: true

    counter_culture :capital_commitment, column_name: 'folio_call_amount_cents',
                                         delta_column: 'folio_call_amount_cents',
                                         execute_after_commit: true

    counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                         delta_column: 'collected_amount_cents',
                                         column_names: {
                                           ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                         },
                                         execute_after_commit: true

    counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'tracking_collected_amount_cents' : nil },
                                         delta_column: 'tracking_collected_amount_cents',
                                         column_names: {
                                           ["capital_remittances.verified = ?", true] => 'tracking_collected_amount_cents'
                                         },
                                         execute_after_commit: true

    # CapitalCommitment and InvestorKyc counters
    counter_culture %i[capital_commitment investor_kyc], column_name: 'call_amount_cents',
                                                         delta_column: 'call_amount_cents',
                                                         execute_after_commit: true

    counter_culture %i[capital_commitment investor_kyc], column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                                         delta_column: 'collected_amount_cents',
                                                         column_names: {
                                                           ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                                         },
                                                         execute_after_commit: true

    counter_culture %i[capital_commitment investor_kyc], column_name: proc { |r| r.verified ? 'other_fee_cents' : nil },
                                                         delta_column: 'other_fee_cents',
                                                         column_names: {
                                                           ["capital_remittances.verified = ?", true] => 'other_fee_cents'
                                                         },
                                                         execute_after_commit: true
  end
end
