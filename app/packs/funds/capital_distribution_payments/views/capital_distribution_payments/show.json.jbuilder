json.partial! "capital_distribution_payments/capital_distribution_payment", capital_distribution_payment: @capital_distribution_payment
# The currency the payable amounts are in (LP mobile app Distribution screen)
json.fund_currency @capital_distribution_payment.fund.currency
# The newest distribution notice this user may see (LP mobile app Distribution screen)
json.notice_document_id MobileDocuments.notice_for(@capital_distribution_payment)
