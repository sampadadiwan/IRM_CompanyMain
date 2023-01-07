Feature: Registration
  Registration should work properly

Scenario Outline: User Registration Successfully
  Given there is an unsaved user "<user>" for an entity "<entity>"
  And I am at the registration page
  When I fill and submit the registration page
  Then I should see the "<msg1>"
  Then the user receives an email with "Confirmation instructions" in the subject
  Then when I click the confirmation link
  # Then I should see the "Your email address has been successfully confirmed."
  Then the user should be confirmed
  Examples:
  	|user		|entity             |msg1											                                              |msg2		  |
  	| 	    |entity_type=Investor     |A message with a confirmation link has been sent to your email address.	|Signed in successfully	|
    |       |entity_type=Company|A message with a confirmation link has been sent to your email address. |Signed in successfully  |
    | 	    |entity_type=Investor     |A message with a confirmation link has been sent to your email address.	|Signed in successfully	|



Scenario Outline: User Registration Successfully
  Given there is a user "<user>" for an entity "<entity>"
  Then the user should have the roles "<roles>"
  Examples:
  	|user		|entity               |roles		|	
  	| 	    |entity_type=Investor       |investor|
    |       |entity_type=Company  |employee   |
    | 	    |entity_type=Holding  |holding   |
    | 	    |entity_type=Investment Advisor  |investor   |
    | 	    |entity_type=Family Office  |investor   |

