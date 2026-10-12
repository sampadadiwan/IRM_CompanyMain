Feature: Workflow Email Notifications and Magic Links
  When a workflow step becomes active, assigned actors receive an email with a
  personalised magic link. Actors can respond via that link without logging in.
  Stale links (step has already moved on) and invalid tokens are handled gracefully.

  # ── Token generation ──────────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Magic link token round-trips correctly
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And there is an actor user "alice@example.com" in the entity
    When I generate a magic link token for actor "alice@example.com" instance 42 step 1
    Then I can verify the token and recover the payload
    And the payload actor_id matches "alice@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: Tampered magic link token is rejected
    Given Im logged in as a user "<user>" for an entity "<entity>"
    When I verify a tampered magic link token
    Then the token verification should return nil

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Email delivery ────────────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Launching a workflow enqueues step-activation emails to first-step actors
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "bob@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Fund Docs"
    And the folder "Fund Docs" has workflow template "LP Review"
    When I launch the workflow for folder "Fund Docs"
    Then a step activation email should be enqueued for "bob@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Advancing to the next step enqueues activation emails for that step's actors
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "carol@example.com" in the entity
    And there is a workflow template "name=Two Step" with 2 steps:
      | name            | states              | quorum_rule | on_reject_rule | actors     |
      | Step One        | Approved,Rejected   | any_one     | stop           | admin      |
      | Step Two        | Approved,Rejected   | any_one     | stop           | actor_user |
    And the entity has a folder "name=Review Docs"
    And the folder "Review Docs" has workflow template "Two Step"
    And the folder "Review Docs" has an active workflow instance for "Two Step"
    When the actor submits "Approved" on the current step of the active instance for "Review Docs"
    Then a step activation email should be enqueued for "carol@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Magic link show page ──────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Valid magic link renders the response form
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "dave@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=LP Docs"
    And the folder "LP Docs" has workflow template "LP Review"
    And the folder "LP Docs" has an active workflow instance for "LP Review"
    When I visit the magic link for actor "dave@example.com" on the active instance at step 1
    Then the magic link page should show the response form
    And the response form should list state "Approved"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Visiting a magic link for a step that has moved on shows moved-on page
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "eve@example.com" in the entity
    And there is a workflow template "name=Two Step" with 2 steps:
      | name       | states            | quorum_rule | on_reject_rule | actors     |
      | Step One   | Approved,Rejected | any_one     | stop           | actor_user |
      | Step Two   | Approved,Rejected | any_one     | stop           | actor_user |
    And the entity has a folder "name=Review Docs"
    And the folder "Review Docs" has workflow template "Two Step"
    And the folder "Review Docs" has an active workflow instance for "Two Step"
    And the instance is now at step 2
    When I visit the magic link for actor "eve@example.com" on the active instance at step 1
    Then the magic link page should show the moved-on message

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: Visiting a magic link after workflow rejection shows moved-on (not invalid)
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "henry@example.com" in the entity
    And there is a workflow template "name=Reject Review" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Rejected Docs"
    And the folder "Rejected Docs" has workflow template "Reject Review"
    And the folder "Rejected Docs" has an active workflow instance for "Reject Review"
    When I submit "Rejected" via magic link for actor "henry@example.com" on step 1 of the active instance
    And I evaluate the magic link routing for actor "henry@example.com" on the instance at step 1
    Then the magic link routing should be "moved_on"
    And the magic link previous response for "henry@example.com" should exist

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: Actor who did not vote sees moved-on but no previous response after workflow rejection
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "ivan@example.com" in the entity
    And there is a second actor "actor2" in the entity
    And there is a workflow template "name=Two Actor Reject" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user,actor2"
    And the entity has a folder "name=Two Actor Docs"
    And the folder "Two Actor Docs" has workflow template "Two Actor Reject"
    And the folder "Two Actor Docs" has an active workflow instance for "Two Actor Reject"
    When I submit "Rejected" via magic link for actor "ivan@example.com" on step 1 of the active instance
    And I evaluate the magic link routing for actor "actor2@example.com" on the instance at step 1
    Then the magic link routing should be "moved_on"
    And the magic link previous response for "actor2@example.com" should not exist

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: An invalid or tampered token shows the invalid page
    Given Im logged in as a user "<user>" for an entity "<entity>"
    When I visit the magic link page with token "this_is_not_a_valid_token"
    Then the magic link page should show the invalid message

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Magic link submit ─────────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Actor submits response via magic link and it is recorded
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "frank@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Fund Reports"
    And the folder "Fund Reports" has workflow template "LP Review"
    And the folder "Fund Reports" has an active workflow instance for "LP Review"
    When I submit "Approved" via magic link for actor "frank@example.com" on step 1 of the active instance
    Then the active instance for "Fund Reports" should have status "complete"
    And the actor response channel should be "email_magic_link"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: Submitting twice via magic link is blocked
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "grace@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=all;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Fund Letters"
    And the folder "Fund Letters" has workflow template "LP Review"
    And the folder "Fund Letters" has an active workflow instance for "LP Review"
    When I submit "Approved" via magic link for actor "grace@example.com" on step 1 of the active instance
    And I try to submit "Rejected" via magic link for actor "grace@example.com" on step 1 of the active instance again
    Then the second magic link submission should be rejected

    Examples:
      | user | entity              |
      |      | entity_type=Company |
