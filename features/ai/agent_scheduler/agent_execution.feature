Feature: Agent Execution via Scheduler
    As a system administrator
    I want support agents to execute correctly when triggered by the scheduler
    So that I can verify the full run lifecycle including failures,successes

    Background:
        Given an entity "Test Company" exists
        And a support agent "Portfolio Company Agent" of type "PortfolioCompanyAgent" exists

    Scenario: Success notification is sent when agent completes
        Given the agent has a schedule with:
            | frequency   | daily |
            | enabled     | true  |
            | run_at_time | 09:00 |
            | timezone    | UTC   |
        And a notification recipient user exists
        And the schedule has notification settings:
            | notify_on_success | true |
        And the schedule's run_at_time is in the future
        When the daily morning job runs
        And the agent runner job executes
        Then the execution log status should be "completed"
        And a success notification should be sent to the configured users



    Scenario: Internal error notification is sent on failure
        Given an entity "Test Company" exists
        And a support agent "Portfolio Agent" of type "PortfolioCompanyAgent" exists
        And a portfolio company "Test Portfolio Co" exists for the entity
        And the agent has a schedule with:
            | frequency         | daily    |
            | enabled           | true     |
            | run_at_time       | 09:00 |
            | notify_on_failure | true     |
        And a notification recipient user exists                          
        And the schedule's run_at_time is in the future
        And the test agent will raise on step two
        When the daily morning job runs
        And the agent runner job executes
        Then the execution log status should be "failed"
        And an internal error notification should be sent

