Feature: Share Transfer
  Can access models as a startup

Scenario Outline: Share Transfer betw Investors
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor1" for another entity "name=From;entity_type=VC"
  And another entity is an investor "category=Lead Investor" in entity
  And given there is a investment "<investment>" for the entity 
  Given there is another user "first_name=Investor2" for another entity "name=To;entity_type=VC"
  And another entity is an investor "category=Co Investor" in entity
  When a share transfer is done for quantity "<quantity>"
  Then the share transfer must be created
  And share transfer should result in a new investment
  And the share transfer should result in the from investment quantity reduced
  And share transfer should result in the aggregate investments being created
  And share transfer should result in the holdings being created     
  And share transfer should not effect the funding round

  Examples:
  	|user	  |entity               |investment                                     | quantity  |
  	|  	      |entity_type=Startup  |quantity=100;investment_instrument=Equity      | 10        |
    |  	      |entity_type=Startup  |quantity=120;investment_instrument=Preferred   | 20        |    


Scenario Outline: Share Conversion rom Pref to Equity
  Given there is a user "first_name=Emp1" for an entity "<entity>"
  Given there is another user "first_name=Investor1" for another entity "name=From;entity_type=VC"
  And another entity is an investor "category=Lead Investor" in entity
  And given there is a investment "<investment>" for the entity 
  When a share conversion is done for quantity "<quantity>"
  Then the share transfer must be created
  And share transfer should result in a new investment
  And the share transfer should result in the from investment quantity reduced
  And share transfer should result in the aggregate investments being created
  And share transfer should result in the holdings being created   
  And share transfer should not effect the funding round  

  Examples:
  	|entity               |investment                                                         | quantity  |
  	|entity_type=Startup  |quantity=100;investment_instrument=Preferred                       | 10        |
    |entity_type=Startup  |quantity=120;investment_instrument=Preferred;preferred_conversion=2| 20        |    
