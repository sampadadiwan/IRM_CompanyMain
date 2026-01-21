Feature: Document Download Job
  As a user
  I want to download a folder with nested structure as a ZIP file
  So that I can access my documents offline in the right organization

  Scenario: Download nested folder structure and verify ZIP and cleanup
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has a folder "name=Root Folder"
    And the entity has a child folder "name=Sub1"
    And folder "Sub1" has sub-folders "Sub2"
    And there is a document "name=DocRoot" in folder "Root Folder"
    And there is a document "name=DocSub1" in folder "Sub1"
    And there is a document "name=DocSub2" in folder "Sub2"
    When I trigger the download for "Root Folder"
    Then the download job should complete successfully
    And the ZIP file should have the following structure:
      | path                      |
      | DocRoot.docx              |
      | Sub1/DocSub1.docx         |
      | Sub1/Sub2/DocSub2.docx    |
    And the temporary directory should be cleaned up

  Scenario: Download folder with a large document (> 2GB)
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has a folder "name=Large Docs"
    And given there is a large document "name=HugeFile;size=2.1GB" under the folder
    When I trigger the download for "Large Docs"
    Then the download job should complete successfully
    And the ZIP file should contain "HugeFile.zip" with Zip64 support
    And the temporary directory should be cleaned up
