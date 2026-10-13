@rack_test
Feature: Document folder path uniqueness

  Every WithFolder record keeps its documents in one folder, named after the record and
  pointed at by document_folder_id. Folder enforces that (full_path, owner, entity) is
  unique, so a record must never end up owning two folders that want the same path.

  On 2026-09-25 production sent ~75 "Validation failed: Full path combination must be
  unique" emails from UpdateDocumentFolderPathJob. The chain was:

    1. WithFolder#setup_document_folder wrote the owner -> folder pointer with a bare `save`.
       An InvestorKyc is created with `validate: false` while PAN/address/bank are blank, so
       that save returned false, nobody checked, and document_folder_id stayed NULL -- while
       the Folder row was created and stamped with `owner`.
    2. Every later touch saw a blank document_folder_id and created ANOTHER folder, named
       from whatever was in memory at the time (including values from a submit that failed
       validation and never reached the database).
    3. When the record finally became valid, document_folder_id latched onto one twin. The
       first rename after that tried to move it onto the other twin's path -- rejected, on
       every edit, 26 Sidekiq attempts each.

  The regular rename path and each link in that chain are pinned below. Model-level only:
  the folder work all hangs off model callbacks and the job, so no browser is involved.

  Background:
    Given there is an entity "name=KYC Entity"
    And the entity has a root folder
    And there is an investor "investor_name=LP Alpha;category=LP" for the entity "name=KYC Entity" with investor_entity "name=Alpha Firm"

  # ---------------------------------------------------------------------------------------
  # The regular path
  # ---------------------------------------------------------------------------------------

  Scenario: A complete KYC gets exactly one folder, linked both ways
    Given there is a KYC "full_name=Alpha Trust" for the investor "LP Alpha"
    Then the KYC should have exactly 1 document folder
    And the KYC document folder should be at its expected path
    And the KYC document folder should be owned by the KYC

  Scenario: Renaming a KYC moves its folder and everything under it
    Given there is a KYC "full_name=Alpha Trust" for the investor "LP Alpha"
    And the KYC document folder has a child folder "Bank Proofs"
    When I rename the KYC to "Alpha Trust II"
    And the folder path job runs for the KYC
    Then the KYC document folder should be at its expected path
    And the KYC document folder should be named "Alpha Trust II"
    And the child folder "Bank Proofs" should be at path "/Investors/LP Alpha/KYC-<id>/Alpha Trust II/Bank Proofs"
    And the KYC should have exactly 1 document folder

  Scenario: Renaming a KYC twice in a row leaves no folder behind
    Given there is a KYC "full_name=Alpha Trust" for the investor "LP Alpha"
    When I rename the KYC to "Alpha Trust II"
    And the folder path job runs for the KYC
    And I rename the KYC to "Alpha Trust III"
    And the folder path job runs for the KYC
    Then the KYC should have exactly 1 document folder
    And the KYC document folder should be at its expected path

  # ---------------------------------------------------------------------------------------
  # Step 1 of the chain: the link must survive an owner that cannot be saved
  # ---------------------------------------------------------------------------------------

  Scenario: An incomplete KYC still records which folder is its own
    # The regression assertion. Before the fix the Folder row was created and knew its owner,
    # but document_folder_id stayed NULL because the owner failed validation.
    Given there is an incomplete KYC for the investor "LP Alpha"
    Then the KYC should not be valid
    When the KYC document folder is set up
    Then the KYC document_folder_id should be persisted
    And the KYC should have exactly 1 document folder
    And the KYC document folder should be owned by the KYC

  Scenario: Touching an incomplete KYC again does not give it a second folder
    Given there is an incomplete KYC for the investor "LP Alpha"
    When the KYC document folder is set up
    And the KYC document folder is set up again from a fresh instance
    Then the KYC should have exactly 1 document folder

  # ---------------------------------------------------------------------------------------
  # Step 2: an already-owned folder is adopted, and unsaved input never names one
  # ---------------------------------------------------------------------------------------

  Scenario: A KYC whose link was lost adopts the folder it already owns
    # Legacy rows: document_folder_id NULL while a folder out there already names this KYC
    # as its owner, and the KYC has since been renamed so the paths no longer match.
    Given there is a KYC "full_name=Gamma Trust" for the investor "LP Alpha"
    And the KYC document folder link is cleared
    And the KYC is renamed in the database to "Gamma Trust Renamed"
    When the KYC document folder is set up
    Then the KYC should have exactly 1 document folder
    And the KYC document folder should be named "Gamma Trust"
    When the folder path job runs for the KYC
    Then the KYC should have exactly 1 document folder
    And the KYC document folder should be at its expected path

  Scenario: A value typed into a failed form never becomes a folder name
    # The 19 Aug event: folder "SP Family Trust" appeared a day before full_name was ever
    # changed to it, because #folder_path read the unsaved attribute.
    Given there is a KYC "full_name=Delta Trust" for the investor "LP Alpha"
    And the KYC document folder link is cleared
    And I type "Typed But Never Saved" into the KYC full name without saving
    When the KYC document folder is set up
    Then no folder should be named "Typed But Never Saved"
    And the KYC should have exactly 1 document folder
    And the KYC document folder should be named "Delta Trust"

  # ---------------------------------------------------------------------------------------
  # Step 3: existing duplicates are merged, not crashed on
  # ---------------------------------------------------------------------------------------

  Scenario: Renaming onto a duplicate the KYC already owns merges instead of failing
    Given there is a KYC "full_name=Beta Trust" for the investor "LP Alpha"
    And the KYC has a stray duplicate folder named "Beta Trust Ltd"
    And the stray duplicate folder has a document "Bank Letter"
    And the stray duplicate folder has a child folder "Old Proofs"
    When I rename the KYC to "Beta Trust Ltd"
    And the folder path job runs for the KYC
    Then the folder path job should not have raised
    And the KYC should have exactly 1 document folder
    And the KYC document folder should be at its expected path
    And the document "Bank Letter" should be in the KYC document folder
    And the child folder "Old Proofs" should be under the KYC document folder

  Scenario: A duplicate whose children collide with the survivor's is merged folder by folder
    Given there is a KYC "full_name=Beta Trust" for the investor "LP Alpha"
    And the KYC document folder has a child folder "Bank Proofs"
    And the KYC has a stray duplicate folder named "Beta Trust Ltd"
    And the stray duplicate folder has a child folder "Bank Proofs"
    And the document "Old Statement" is in the stray duplicate's child folder "Bank Proofs"
    When I rename the KYC to "Beta Trust Ltd"
    And the folder path job runs for the KYC
    Then the folder path job should not have raised
    And the KYC should have exactly 1 document folder
    And the KYC document folder should have exactly 1 child folder named "Bank Proofs"
    And the document "Old Statement" should be in the child folder "Bank Proofs"

  Scenario: The job is dropped rather than retried 26 times when it cannot win
    # Whatever else goes wrong, a path repair must not turn into an inbox full of identical
    # error mails: the inputs do not change between attempts.
    Then UpdateDocumentFolderPathJob should discard ActiveRecord::RecordInvalid
