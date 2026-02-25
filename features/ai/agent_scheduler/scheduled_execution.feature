Feature: Scheduled Agent Execution
    As a system Administrator
    I want support agents to run automatically at their scheduled times
    So that tasks are performed without manual intervention


    Background:
        # This runs before EACH scenario
        # Sets up the basic entities we need
        Given an entity "Test Company" exists
        And a support agent "Test Agent" of type "PortfolioCompanyAgent" exists


    Scenario: Agent runs when schedule is due and enabled
        Given the agent has a schedule with:
            | frequency   | daily |
            | enabled     | true  |
            | run_at_time | 09:00 |
            | timezone    | UTC   |
        And the schedule's next_run_at is in the past
        When the scheduler polling job runs
        Then an execution log should be created
        And the execution log should have:
            | status       | queued    |
            | trigger_type | scheduled |
        And the schedule's next_run_at should be in the future

    Scenario: Agent does not run when schedule is due but disabled
        Given the agent has a schedule with:
            | frequency   | daily |
            | enabled     | false |
            | run_at_time | 09:00 |
            | timezone    | UTC   |
        And the schedule's next_run_at is in the past
        When the scheduler polling job runs
        Then no execution log should be created


