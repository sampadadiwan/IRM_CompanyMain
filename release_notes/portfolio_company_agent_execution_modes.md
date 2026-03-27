Path 1
Controller
  └─► SupportAgentJob.perform_later(support_agent_id:, batch_ids:, batch_ids_type: "Investor",
                                     user_id:, execution_mode: :adhoc_batch)
        └─► fetch_batch_targets() → validates IDs, returns Investor records
        └─► PortfolioCompanyAgent.process_batch(...)       ← CLASS METHOD
              └─► Loops each target → agent.wtf?(target: target, ...)  ← one Trailblazer call per company
              └─► ctx[:portfolio_companies] is BLANK (target: not targets:)
              └─► initialize_agent → single-company branch
              └─► AgentChartJob.perform_later(user_id, portfolio_company_ids:, execution_mode: :adhoc_batch)
              └─► send_batch_summary notification (shown in chat UI)
Path 2 — Scheduled Run
Triggered by AgentRunnerJob (via AgentSchedule / Sidekiq cron)
AgentRunnerJob.perform(execution_log_id)
  └─► targets = PortfolioCompanyAgent.new.targets(entity_id)  → all 54 companies
  └─► execute_portfolio_company_batch(targets)
        └─► PortfolioCompanyAgent.call(support_agent_id:, targets: targets, entity_id:)  ← ONE call for ALL
              └─► initialize_agent → targets: branch → ctx[:portfolio_companies] = all 54
              └─► check_kpi_submission → loops ctx[:portfolio_companies]
              └─► check_document_presence → loops ctx[:portfolio_companies]
              └─► check_valuations → loops ctx[:portfolio_companies]
              └─► generate_progress_reports → loops, calls super(model: pc) per company,
                                              broadcasts each row,
                                              AgentChartJob.perform_later(nil, execution_mode: :scheduled)
Path 3
Controller
  └─► SupportAgentJob.perform_later(support_agent_id:, target_id: 296, target_type: "Investor",
                                     user_id:, with_steps: true,
                                     execution_mode: :single_company_with_steps)
        └─► targets = [Investor.find(296)]                    ← single element array
        └─► target_with_steps = true
        └─► agent_instance.initialize_report_with_steps(...)  ← creates SupportAgentReport with steps pre-populated
        └─► PortfolioCompanyAgent.call(target: target, support_agent_report: report, ...)
              └─► initialize_agent → single-company branch (target:, no targets:)
              └─► ctx[:portfolio_companies] is BLANK
              └─► each step broadcasts progress via Turbo Stream in real time
              └─► generate_progress_reports → super(), broadcast_portco_row, AgentChartJob(user_id, portfolio_company_id:)
        └─► send_notification with "View Report" link (single-target notification)
