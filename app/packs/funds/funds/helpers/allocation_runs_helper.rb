module AllocationRunsHelper
  # "Mark as crashed" popup on Previous Runs: what clicking does, as action-summary cards
  # (the same Immediate Actions layout as Unlock, built by fs_action_summary)
  def allocation_run_crash_action_summary(run)
    period = "#{l(run.start_date)} – #{l(run.end_date)}"
    fs_action_summary([
                        ["amber", "ti-player-stop", "Run marked as crashed",
                         "No server is running it: its process stopped, or its job is still waiting in the queue (a queued job will not start). The status becomes \"Crashed\"."],
                        ["blue", "ti-list-details", "Entries it wrote stay",
                         "Anything it already wrote for #{period} stays until the next run for this period replaces it, so re-run the period."],
                        ["green", "ti-player-play", "Fund free to run again",
                         "You can start a new allocation run on this fund straight away."]
                      ], intro_action: "Mark as crashed")
  end
end
