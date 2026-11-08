# frozen_string_literal: true

module Dr
  # Removes OLD backup jobs from the ubuntu and root crontabs of a DB box, over an already-open
  # Net::SSH session.
  #
  # Why: DR database servers are launched from a weekly snapshot of the LIVE DB box, whose ubuntu
  # crontab still runs /home/ubuntu/backup_db.sh - a writer with the live bucket hard-coded that
  # ignores the armed marker. Left alone it runs on every DR primary AND replica, beside the baked
  # schedule: a second writer on one backup chain (openspec fix-dr-backup-cron-after-restore).
  #
  # Called twice per DR, deliberately:
  # - AwsUtils#setup_infra, right after the servers exist (best effort, shrinks the window in
  #   which a cloned job can fire before the restore);
  # - run_baked_restore in lib/tasks/backup_db.rake, before every restore (the guaranteed pass).
  #
  # Never raises: a failure is printed loudly, and dr:verify then fails the stack on
  # "Primary backup schedule (single writer)" / "Replica has no backup writer".
  # rubocop:disable Rails/Output -- operator-facing: these lines are read live in the DR
  # transcript (docs/operations/dr/runs/*.log), like every other DR rake step's output
  module OldBackupJobs
    # Each user whose crontab can hold a job, and the crontab command that edits it
    CRONTABS = { "ubuntu" => "crontab", "root" => "sudo crontab -u root" }.freeze

    module_function

    # Strips old backup jobs from every crontab on the box. Returns the number of lines removed
    # (nil on an unexpected error).
    def strip!(ssh, prefix: "")
      require "base64" # a bundled gem from Ruby 3.4 on - not loaded unless required
      CRONTABS.sum do |user, crontab|
        # 2>&1: "no crontab for <user>" goes to stderr; split_crontab drops it
        split = BackupSchedule.split_crontab(ssh.exec!("#{crontab} -l 2>&1"))
        next 0 if split[:removed].empty?

        split[:removed].each { |line| puts "#{prefix}🧹 Removing old backup job from #{user}'s crontab: #{line}" }
        # Rewrite with the kept lines only (an empty crontab if nothing is left). Base64 keeps the
        # quotes and $ in the @reboot docker lines intact through both shells.
        kept = split[:kept].empty? ? "" : "#{split[:kept].join("\n")}\n"
        written = ssh.exec!("echo #{Base64.strict_encode64(kept)} | base64 -d | #{crontab} - && echo OK").to_s

        # Re-read to prove the old jobs are gone, rather than trusting the write
        left = BackupSchedule.old_jobs(ssh.exec!("#{crontab} -l 2>&1"))
        if written.include?("OK") && left.empty?
          puts "#{prefix}✓ #{user}'s crontab: #{split[:removed].size} old backup job(s) removed, #{split[:kept].size} line(s) kept"
        else
          puts "#{prefix}❌ Could NOT strip old backup jobs from #{user}'s crontab (still there: #{left.join(' | ')}) — a second backup writer remains"
        end
        split[:removed].size
      end
    rescue StandardError => e
      puts "#{prefix}❌ Old backup job strip failed: #{e.message} — check this box's crontabs by hand"
      nil
    end
  end
  # rubocop:enable Rails/Output
end
