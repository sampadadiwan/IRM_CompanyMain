Feature: Commitment Adjustments
  Adjustments to capital commitments

Scenario Outline: Create a commitment adjustment
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor 
  When a commitment adjustment "<adjustment>" is created 
  Then the capital commitment should have a committed amount "<new_committed_amount_cents>"
  And the capital commitment should have a arrears amount "<new_arrears_amount_cents>"
  And when the adjustment is destroyed
  Then the capital commitment should have a committed amount "100000000"
  And the capital commitment should have a arrears amount "0"
  

    Examples:
        | adjustment                                    | new_committed_amount_cents | new_arrears_amount_cents |
        | folio_amount_cents=10000000;adjustment_type=Top Up  | 110000000                  | 0                 |
        | folio_amount_cents=-10000000;adjustment_type=Top Up | 90000000                   | 0                 |
        | folio_amount_cents=-100000000;adjustment_type=Top Up | 0                         | 0                 |
        | folio_amount_cents=10000000;adjustment_type=Arrear  | 100000000                  | 10000000                 |
        | folio_amount_cents=-10000000;adjustment_type=Arrear | 100000000                  | -10000000                |
  
Scenario Outline: Create a commitment adjustment for 0 dollar commitment
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=0;folio_currency=INR" for the last investor 
  When a commitment adjustment "<adjustment>" is created 
  And the capital commitment is resaved
  Then the capital commitment should have a committed amount "<new_committed_amount_cents>"
  And the capital commitment should have a orig commitment amount "0" 
  And the capital commitment should have a arrears amount "<new_arrears_amount_cents>"
  And when the adjustment is destroyed
  Then the capital commitment should have a committed amount "0"
  And the capital commitment should have a arrears amount "0"
  

    Examples:
        | adjustment                                    | new_committed_amount_cents | new_arrears_amount_cents |
        | folio_amount_cents=10000000;adjustment_type=Top Up  | 10000000                  | 0                 |
        | folio_amount_cents=10000000;adjustment_type=Top Up | 10000000                   | 0                 |
        
  

Scenario Outline: Create a commitment adjustment for a remittance
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor 
  Given there is a capital call "close_percentages={'First Close':'20'}"
  Given there are payments for each remittance
  When a commitment adjustment "<adjustment>" is created for the last remittance 
  Then a reverse remittance payment must be generated for the remittance
  Given the remittances are verified
  Then the capital commitment should have a committed amount "<new_committed_amount_cents>"
  And the capital commitment should have a arrears amount "<new_arrears_amount_cents>"
  And the last remittance should have a arrears amount "<new_arrears_amount_cents>"
  And the collected amounts must be computed properly

    Examples:
        | adjustment                                    | new_committed_amount_cents | new_arrears_amount_cents |
        | folio_amount_cents=10000000;adjustment_type=Arrear  | 100000000            | 10000000                 |
        | folio_amount_cents=-10000000;adjustment_type=Arrear | 100000000            | -10000000                |
  
  