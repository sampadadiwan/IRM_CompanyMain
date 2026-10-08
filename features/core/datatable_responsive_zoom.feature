@rack_test
Feature: DataTable controller and responsive zoom patch
  Tables on index pages are set up by the `datatable` Stimulus controller. Its Responsive
  zoom-tolerance patch must not call array methods on Responsive's columns, which are a DataTables
  Api instance (no forEach) and made every table throw at a fractional zoom.

Background:
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  And I am on the favorites page

# H1
Scenario: The datatable controller is attached to the index table
  Then the data table is inside a "datatable" controller
  And the table column "Actions" is present
  And the importmap pins the "datatable" Stimulus controller

# X1
Scenario: The zoom patch does not call array methods on Responsive's columns
  Then the "datatable" controller source installs the responsive zoom patch
  And the "datatable" controller source does not call array methods on the responsive columns
