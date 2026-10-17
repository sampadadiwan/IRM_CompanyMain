json.partial! "capital_remittances/capital_remittance", capital_remittance: @capital_remittance
# The newest call notice this user may see (LP mobile app Capital call screen — lp-mobile-app H6, E22)
json.notice_document_id MobileDocuments.notice_for(@capital_remittance)
