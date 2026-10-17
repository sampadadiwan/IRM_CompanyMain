json.partial! "documents/document", document: @document
# For the LP mobile app's Document screen: this user's signature status and how to sign
# (lp-mobile-app H18 Digio in-app, E21 DocuSign by email)
json.merge! MobileDocumentJson.signing(@document, current_user)
