Feature: Note
  Can create and view a note as a company

Scenario Outline: Create new note
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "<investor>"
  And I am at the investor page
  When I create a new note "Hi, How are you?"
  Then I should see the "<msg>"
  And an note should be created
  And I should see the note details on the details page
  And I should see the note in all notes page

  Examples:
  	|user	    |entity               |investor     |msg	|
  	|  	        |entity_type=Company  |name=Sequoia |Note was successfully created|
    |  	        |entity_type=Company  |name=Bearing |Note was successfully created|
