# frozen_string_literal: true

# Marks the processes of a DR DRILL stack (openspec fix-dr-drill-hygiene).
#
# aws:dr_drill writes DR_DRILL_STACK=<region> into the drill branch's .env, so every process on
# the drill's servers knows it is a rehearsal:
# - its error mail is tagged "[DR DRILL <region>]", so it is never mistaken for a live incident;
# - it never sends a critical WhatsApp page (CriticalErrorWhatsapp.enabled?) - a drill must not
#   wake anyone, and its errors still arrive as tagged mail.
# A real recovery never sets it, so a recovered production still pages as before.
#
# Plain Ruby, required at boot by config/initializers/exception_notification.rb and
# lib/critical_error_whatsapp.rb (the notifier must not autoload at the moment it fires).
module DrillStack
  module_function

  # The drill's region ("ap-south-2"), or nil on every real environment
  def region(env = ENV)
    value = env["DR_DRILL_STACK"].to_s.strip
    value.empty? ? nil : value
  end

  def drill?(env = ENV)
    !region(env).nil?
  end

  # dr:verify's check that a stack is marked correctly for its kind of run.
  # expected_drill: this run is a drill (DR_DRILL=true, forwarded by cap).
  # Returns a Dr::BackupSchedule::Grade (resolved at call time, after boot).
  def grade_mark(expected_drill:, env: ENV)
    grade = Dr::BackupSchedule::Grade
    if expected_drill
      # A drill server without the mark would page WhatsApp and send untagged mail
      return grade.new(:ok, "drill servers marked (#{region(env)}): tagged mail, no WhatsApp pages") if drill?(env)

      grade.new(:fail, "drill servers are NOT marked (no DR_DRILL_STACK in .env) — they would page WhatsApp like a live outage")
    else
      # A recovered production marked as a drill would never page anyone
      return grade.new(:ok, "not marked as a drill — critical alerts page as normal") unless drill?(env)

      grade.new(:fail, "this recovered stack is marked as a drill (DR_DRILL_STACK=#{region(env)}) — it will NEVER page; " \
                       "remove DR_DRILL_STACK from .env and redeploy")
    end
  end

  # The error mail subject prefix: unchanged on a real environment, tagged on a drill stack
  def email_prefix(rails_env:, base_domain:, env: ENV)
    tag = drill?(env) ? "[DR DRILL #{region(env)}]" : ""
    "[Error]#{tag} #{rails_env}:(#{base_domain})"
  end
end
