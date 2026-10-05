# One field Document Checks may fill in or compare on a record, as a registry entry describes it.
#   name    - the column or custom-field name ("PAN", "dp")
#   label   - what users see in the dropdown and in results ("PAN", "DP ID")
#   storage - :column (an attribute) or :json (a custom field in json_fields)
#   loose   - names and addresses: compared ignoring word order
#   date    - parsed and compared as a Date
# See openspec/changes/document-checks/design.md (card ② Registry).
module DocChecks
  Field = Struct.new(:name, :label, :storage, :loose, :date, keyword_init: true) do
    def loose? = loose == true
    def date? = date == true
  end
end
