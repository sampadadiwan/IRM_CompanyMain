Feature: Compliance
  Compliance tests for error rates



# Scenario Outline: Run compliance checks
#   Given there is a user "" for an entity "entity_type=Investment Fund"
#   Given the user has role "company_admin"
#   Given there is a fund "name=Marco Fund"
#   And Given there is an investor "investor_name=Investor1"
#   And Given there is are "<commitment_count>" commitment "<commitment>"
#   And Given there is a capital call "call_basis=Percentage of Commitment;approved=true"
#   And Given the Remittances are marked as "<remittance_status>"
#   And Given there is a portfolio investment "<portfolio_investment>"
#   And Given the compliance rules "ai_rules.xlsx"
#   Then when I run the compliance agent
#   Then all the checks must be run
#   And the audit_log must be present for each check
#   And the out put of each check must be "<check_output>"

# Examples:
#   	|commitment_count |commitment               |remittance_status        | portfolio_investment | check_output |
#     |2      | committed_amount_cents=100000     |verified=true;status=Paid|
  

  
