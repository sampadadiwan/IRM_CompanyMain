Feature: Secondary Sale
  Can create and view a sale as a company

Scenario Outline: Create new sale
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the sales page
  When I create a new sale "<sale>"
  Then I should see the "<msg>"
  And an sale should be created
  And I should see the sale details on the details page
  And I should see the sale in all sales page

  Examples:
  	|user	    |entity               |sale             |msg	|
  	|  	        |entity_type=Company  |name=Grand Sale  |Secondary sale was successfully created|
    |  	        |entity_type=Company  |name=Winter Sale |Secondary sale was successfully created|


Scenario Outline: Sale Notifications 
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  And the sale has an allocation SPA template
  And the sale has an allocation SPA template
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  And Given I upload a offer file "offers_allocate.xlsx"
  And when the offers are approved
  And given I upload an interests file "interests_allocate.xlsx"
  Given the email queue is cleared
  Given we trigger a notification "Send Sale Open : To Sellers" for the sale
  Then each seller must receive email with subject "Secondary Sale: #{@sale.name} by #{@sale.entity.name}, open for offers"
  Given the email queue is cleared
  Given we trigger a notification "Send Offer Reminder : To Sellers" for the sale
  Then each seller must receive email with subject "Secondary Sale: #{@sale.name} by #{@sale.entity.name}, reminder to enter your offer"
  Given the email queue is cleared
  Given we trigger a notification "Send Sale Open : To Buyers" for the sale
  Then each buyer must receive email with subject "Secondary Sale: #{@sale.name} by #{@sale.entity.name}, open for interests"
  Given the email queue is cleared
  Given we trigger a notification "Send Interest Reminder : To Buyers" for the sale
  Then each buyer must receive email with subject "Secondary Sale: #{@sale.name} by #{@sale.entity.name}, reminder to enter your interest"
  Then when the allocation is done
  Then when the allocations are verified
  And when the allocations SPA generation is triggered 
  Then the SPAs must be generated for each verified allocation
  Given the email queue is cleared
  Given we trigger a notification "Allocation Notification : To All" for the sale
  Then each seller must receive email with subject "Secondary Sale: #{@sale.name} allocation complete."
  Then each buyer must receive email with subject "Secondary Sale: #{@sale.name} allocation complete."
  Given the email queue is cleared
  Given we trigger a notification "Confirm SPA Notification : To Sellers" for the sale
  Then each seller must receive email with subject "Secondary Sale: #{@sale.name}, please accept uploaded SPA."
  Given the email queue is cleared
  Given we trigger a notification "Confirm SPA Notification : To Buyers" for the sale
  Then each buyer must receive email with subject "Secondary Sale: #{@sale.name}, please accept uploaded SPA."

  Examples:
  	|allocation_percentage |interest_count |interest                       |offer	                      |entity                     |sale                                     |
  	| .5                   |1              |quantity=50;short_listed_status=short_listed  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;price_type=Fixed Price;final_price=10000;percent_allowed=100  |
    | 1.0                  |2              |quantity=50;short_listed_status=short_listed  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;price_type=Fixed Price;final_price=10000;percent_allowed=100  |

