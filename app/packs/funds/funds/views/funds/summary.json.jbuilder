# The figures on the fund's overview, as JSON (funds-json-api-hardening ⑦ — H8 E19). Read from the
# fund's own rollup columns, so they always equal what the overview shows. Major units.
json.id @fund.id
json.name @fund.name
json.currency @fund.currency
json.tracking_currency @fund.tracking_currency

json.committed_amount @fund.committed_amount.to_f
json.call_amount @fund.call_amount.to_f
json.collected_amount @fund.collected_amount.to_f
# Due = called − collected, as on the overview
json.due_amount (@fund.call_amount - @fund.collected_amount).to_f
json.distribution_amount @fund.distribution_amount.to_f

# E19: the same figures in the tracking currency
json.tracking_committed_amount @fund.tracking_committed_amount.to_f
json.tracking_call_amount @fund.tracking_call_amount.to_f
json.tracking_collected_amount @fund.tracking_collected_amount.to_f
json.tracking_distribution_amount @fund.tracking_distribution_amount.to_f

json.capital_commitments_count @fund.capital_commitments.count
json.capital_calls_count @fund.capital_calls.count
json.capital_distributions_count @fund.capital_distributions.count
