# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'tempfile'

module IncidentWatch
  # Takes a "new" incident and turns it into an RCA plus a patched branch.
  #
  # The run happens in a dedicated git worktree rather than the checkout you are sitting
  # in. That is the whole reason this is safe to leave on a cron: an unattended Claude run
  # can edit, test and commit freely without ever touching your working tree, your index,
  # or the branch you happen to have checked out.
  class Dispatcher
    def initialize(repo_root, config, store, logger: nil)
      @repo_root = repo_root
      @config = config
      @store = store
      @logger = logger
    end

    def dispatch(incident, force: false)
      fingerprint = incident['fingerprint']

      # `failed` is retryable by definition - that is what the Retry button is for.
      # Anything further along (analysed/done/patching) needs an explicit force, so a stray
      # click cannot redo work that already succeeded.
      unless force || %w[new failed].include?(incident['state'])
        log "#{fingerprint}: state=#{incident['state']}, skipping (use --force to re-run)"
        return :skipped
      end

      branch = "#{@config.dig('dispatch', 'branch_prefix')}#{fingerprint}"
      worktree = File.join(@repo_root, @config.dig('dispatch', 'worktree_dir'), "incident-#{fingerprint}")

      log "#{fingerprint}: #{incident['exception_class']} in #{incident['location'] || 'unknown'} -> #{branch}"
      @store.update_state(fingerprint, 'dispatched', 'branch' => branch, 'worktree' => worktree)

      begin
        prepare_worktree(worktree, branch)
        incident_path = stage_run_inputs(worktree, fingerprint)
        status, output = run_claude(worktree, incident_path, fingerprint, stage: :analyse)
        finish_analysis(fingerprint, worktree, branch, status, output)
      rescue StandardError => e
        log "#{fingerprint}: dispatch failed - #{e.class}: #{e.message}"
        @store.update_state(fingerprint, 'failed', 'error' => "#{e.class}: #{e.message}")
        :failed
      end
    end

    # Publish an already-analysed incident on demand: push the branch and open the draft PR.
    # This is what the dashboard's "Create PR" button calls once a human has read the RCA and
    # decided the fix is worth reviewing.
    #
    # Returns the same hash shape publish/1 does, and persists it, so the dashboard picks the
    # PR link up on its next render.
    def publish_incident(fingerprint)
      incident = @store.find(fingerprint) or return { 'pr_error' => "no incident #{fingerprint}" }

      return { 'pr_error' => "incident is #{incident['state']}, not done - nothing to publish yet" } unless incident['state'] == 'done'

      branch = incident['branch']
      return { 'pr_error' => 'incident has no branch' } if branch.to_s.empty?

      result = publish(fingerprint, branch, incident['rca_doc'], force: true)
      @store.update_state(fingerprint, 'done', result) unless result.empty?
      result
    end

    # Stage 2: implement the fix you approved, then publish it.
    #
    # Runs in the same worktree and on the same branch as the analysis, so the PR carries
    # the RCA commit and the fix commit together.
    def patch_incident(fingerprint)
      incident = @store.find(fingerprint) or return :missing

      unless incident['state'] == 'analysed'
        log "#{fingerprint}: state=#{incident['state']}, only an analysed incident can be patched"
        return :skipped
      end

      branch = incident['branch']
      worktree = incident['worktree']
      @store.update_state(fingerprint, 'patching')

      begin
        # The worktree may have been cleaned up between analysis and approval.
        prepare_worktree(worktree, branch)
        incident_path = stage_run_inputs(worktree, fingerprint)
        before = commit_count(branch)
        status, output = run_claude(worktree, incident_path, fingerprint, stage: :patch)
        finish_patch(fingerprint, branch, before, status, output)
      rescue StandardError => e
        log "#{fingerprint}: patch failed - #{e.class}: #{e.message}"
        @store.update_state(fingerprint, 'failed', 'error' => "#{e.class}: #{e.message}")
        :failed
      end
    end

    # Retry a failed incident, resuming at the right stage.
    #
    # Which stage that is comes from git, not from the stored state: the state says only
    # "failed", but the branch shows exactly how far the work actually got. A run that
    # produced an RCA and a patch and then failed while opening the PR must not redo the
    # analysis - that would waste tokens and throw away good work.
    def retry_incident(fingerprint)
      incident = @store.find(fingerprint) or return :missing

      branch = incident['branch']
      if branch.to_s.empty? || !branch_exists?(branch)
        # Nothing was ever built. Start over.
        return dispatch(incident, force: true)
      end

      files = changed_files(branch)
      has_rca = files.any? { |f| f.start_with?('docs/incidents/') }
      has_patch = files.any? { |f| !f.start_with?('docs/incidents/') }

      if has_patch
        # RCA and patch are both committed; the failure was in publishing. Just publish.
        log "#{fingerprint}: retry - work is complete, retrying publish only"
        result = publish(fingerprint, branch, incident['rca_doc'], force: true)
        @store.update_state(fingerprint, 'done', { 'error' => nil }.merge(result))
        result['pr_error'] ? :failed : :done
      elsif has_rca
        # Analysis succeeded, patching did not. Resume at stage 2.
        log "#{fingerprint}: retry - RCA exists, resuming at the patch stage"
        @store.update_state(fingerprint, 'analysed', 'error' => nil)
        patch_incident(fingerprint)
      else
        # The branch exists but carries nothing usable - reset it and re-analyse.
        log "#{fingerprint}: retry - nothing committed, re-running analysis from a clean branch"
        reset_worktree(incident['worktree'])
        dispatch(incident, force: true)
      end
    end

    private

    # --- git ---------------------------------------------------------------------------

    def prepare_worktree(worktree, branch)
      # Reuse an existing worktree so a re-run continues on the same branch instead of
      # exploding on "branch already exists".
      if File.directory?(File.join(worktree, '.git')) || File.exist?(File.join(worktree, '.git'))
        log "reusing worktree #{worktree}"
        return
      end

      FileUtils.mkdir_p(File.dirname(worktree))
      base = resolve_base_ref

      if branch_exists?(branch)
        git!('worktree', 'add', worktree, branch)
      else
        git!('worktree', 'add', '-b', branch, worktree, base)
      end
      log "created worktree #{worktree} from #{base}"
    end

    # Prefer the configured base (origin/main) so the fix is built on what is actually
    # deployed, not on whatever local work is in progress. Fall back to HEAD when the ref
    # is unavailable - a cron box that cannot reach the remote should still produce an RCA.
    def resolve_base_ref
      configured = @config.dig('dispatch', 'base_ref')
      # A quiet fetch keeps origin/main current; failure here is not fatal.
      git('fetch', '--quiet', 'origin')
      return configured if ref_exists?(configured)

      log "base ref #{configured} not found, falling back to HEAD"
      'HEAD'
    end

    # Drop whatever a failed run left on the branch so a retry starts from the same place
    # the first attempt did. Only ever used on an incident's own worktree.
    def reset_worktree(worktree)
      return if worktree.to_s.empty? || !File.exist?(File.join(worktree, '.git'))

      base = @config.dig('dispatch', 'base_ref')
      Open3.capture3('git', '-C', worktree, 'reset', '--hard', base)
    end

    def ref_exists?(ref)
      _, status = git('rev-parse', '--verify', '--quiet', ref)
      status.success?
    end

    def branch_exists?(branch)
      _, status = git('rev-parse', '--verify', '--quiet', "refs/heads/#{branch}")
      status.success?
    end

    def git(*)
      out, err, status = Open3.capture3('git', '-C', @repo_root, *)
      [out.strip + err.strip, status]
    end

    def git!(*args)
      out, status = git(*args)
      raise Error, "git #{args.join(' ')} failed: #{out}" unless status.success?

      out
    end

    # --- claude ------------------------------------------------------------------------

    # Put everything the RCA run needs inside the worktree, so it can work from relative
    # paths and never needs filesystem access outside its own directory.
    #
    # Two things get staged, and both live in gitignored directories so neither can end up
    # in the commit:
    #
    #   * the incident JSON, under tmp/
    #   * the incident-rca skill, under .claude/skills/
    #
    # The skill has to be copied because .claude/ is gitignored in this repo, so a fresh
    # worktree checked out from origin/main would not contain it and the /incident-rca
    # invocation would silently fall back to a generic run.
    def stage_run_inputs(worktree, fingerprint)
      relative = File.join('tmp', 'incident_watch', 'incidents', "#{fingerprint}.json")
      target = File.join(worktree, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(@store.path_for(fingerprint), target)

      # The cucumber wrapper, staged under tmp/ so it adds no untracked noise to git status
      # inside the worktree. See the comments in the script for why a fixed-name wrapper is
      # needed instead of allowlisting an inline TEST_ENV_NUMBER= prefix.
      runner_source = File.join(@repo_root, 'lib', 'incident_watch', 'rca-cucumber')
      if File.exist?(runner_source)
        runner_target = File.join(worktree, 'tmp', 'incident_watch', 'rca-cucumber')
        FileUtils.cp(runner_source, runner_target)
        FileUtils.chmod(0o755, runner_target)
      end

      # Both stages' skills are staged, so approving a patch does not need a re-stage.
      skill_target = File.join(worktree, '.claude', 'skills')
      FileUtils.mkdir_p(skill_target)
      %w[incident-rca incident-patch].each do |skill|
        source = File.join(@repo_root, '.claude', 'skills', skill)
        if File.directory?(source)
          FileUtils.cp_r(source, skill_target, remove_destination: true)
        else
          log "WARNING: #{source} not found; the #{skill} run will not have its instructions"
        end
      end

      relative
    end

    # stage: :analyse runs /incident-rca, which writes the RCA and changes no code.
    # stage: :patch   runs /incident-patch, which implements the fix you approved.
    # They differ only in the skill invoked and the tools granted - the patch stage is the
    # only one that can touch application code.
    STAGES = {
      analyse: { skill: 'incident-rca', tools: 'analyse_allowed_tools' },
      patch: { skill: 'incident-patch', tools: 'allowed_tools' }
    }.freeze

    def run_claude(worktree, incident_path, fingerprint, stage:)
      dispatch = @config['dispatch']
      spec = STAGES.fetch(stage)
      cmd = [
        'claude', '-p',
        "/#{spec[:skill]} #{incident_path}",
        '--model', dispatch['model'].to_s,
        # acceptEdits lets it write without a prompt; the allowlist below is what keeps an
        # unattended run from reaching anything it should not.
        '--permission-mode', 'acceptEdits',
        '--allowedTools', Array(dispatch[spec[:tools]]).join(','),
        '--output-format', 'json'
      ]

      log "running: #{cmd.map { |a| Shellwords.escape(a) }.join(' ')}"

      # Record the child's pid so an interrupted run can be detected later. Without it, a
      # dispatcher killed mid-run leaves the incident stuck in "dispatched" forever: nothing
      # would ever retry it, and the dashboard would show a progress bar climbing past 100%.
      on_spawn = ->(pid) { @store.update_state(fingerprint, 'dispatched', 'run_pid' => pid) }

      capture_with_timeout(cmd, worktree, dispatch['timeout_seconds'].to_i,
                           run_log_path(fingerprint, stage), on_spawn)
    end

    # tmp/incident_watch/logs/<fingerprint>.log - everything the headless run printed.
    # Without this the output would live only in a local variable and be discarded on
    # success, which makes a bad run impossible to review after the fact.
    def run_log_path(fingerprint, stage)
      dir = File.join(@store.root, 'logs')
      FileUtils.mkdir_p(dir)
      File.join(dir, "#{fingerprint}-#{stage}.log")
    end

    # Run the child with a watchdog. A wedged RCA run must not hold the cron slot open
    # forever, and killing the process group takes any tools it spawned down with it.
    def capture_with_timeout(cmd, chdir, timeout, log_path = nil, on_spawn = nil)
      out_r, out_w = IO.pipe
      pid = Process.spawn(*cmd, chdir: chdir, out: out_w, err: %i[child out], pgroup: true)
      out_w.close
      on_spawn&.call(pid)

      output = +''
      # Tee to disk as it arrives rather than writing at the end, so a run that is killed by
      # the watchdog still leaves behind whatever it managed to say.
      reader = Thread.new do
        sink = log_path && File.open(log_path, 'w')
        sink&.sync = true
        begin
          while (chunk = out_r.read(4096))
            output << chunk
            sink&.write(chunk)
          end
        ensure
          sink&.close
        end
      end

      timed_out = false
      waiter = Thread.new do
        sleep timeout
        timed_out = true
        # Negative pid signals the whole process group.
        Process.kill('TERM', -pid)
        sleep 10
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH
        nil # already exited - the happy path
      end

      _, status = Process.waitpid2(pid)
      waiter.kill
      reader.join
      out_r.close

      raise Error, "RCA run exceeded #{timeout}s and was killed" if timed_out

      [status, output]
    end

    # --- outcome -----------------------------------------------------------------------

    # Stage 1 outcome. Trust git, not the model's prose: the incident only advances if the
    # branch actually carries a commit that the base ref does not.
    #
    # It also enforces the promise that analysis changes no code. If the run edited anything
    # outside docs/incidents/ the incident is marked failed rather than presented as a clean
    # RCA - silently shipping an unrequested patch would defeat the point of the gate.
    def finish_analysis(fingerprint, worktree, branch, status, output)
      commits = commit_count(branch)
      rca_doc = find_rca_doc(worktree, fingerprint)
      summary = extract_summary(output)
      stray = changed_files(branch).reject { |f| f.start_with?('docs/incidents/') }

      if !status.success?
        fail_incident(fingerprint, "claude exited #{status.exitstatus}", summary)
      elsif commits.zero?
        fail_incident(fingerprint, 'no RCA was committed', summary)
      elsif rca_doc.nil?
        fail_incident(fingerprint, 'commit produced no docs/incidents/ document', summary)
      elsif stray.any?
        fail_incident(fingerprint,
                      "analysis stage changed code it should not have: #{stray.join(', ')}",
                      summary)
      else
        @store.update_state(fingerprint, 'analysed',
                            'branch' => branch, 'commits' => commits,
                            'rca_doc' => rca_doc, 'summary' => summary, 'run_pid' => nil)
        log "#{fingerprint}: analysed - RCA on #{branch}, awaiting approval"
        :analysed
      end
    end

    # Stage 2 outcome: require a NEW commit on top of the RCA one, then open the draft PR.
    def finish_patch(fingerprint, branch, commits_before, status, output)
      commits = commit_count(branch)
      summary = extract_summary(output)

      if !status.success?
        fail_incident(fingerprint, "claude exited #{status.exitstatus}", summary)
      elsif commits <= commits_before
        fail_incident(fingerprint, 'no patch was committed', summary)
      else
        incident = @store.find(fingerprint) || {}
        # Approving the RCA is the approval to publish, so force past the auto-publish flag.
        pr = publish(fingerprint, branch, incident['rca_doc'], force: true)
        @store.update_state(fingerprint, 'done',
                            { 'commits' => commits, 'summary' => summary, 'run_pid' => nil }.merge(pr))
        log "#{fingerprint}: done - #{commits} commit(s)#{" - #{pr['pr_url']}" if pr['pr_url']}"
        :done
      end
    end

    def fail_incident(fingerprint, reason, summary = nil)
      @store.update_state(fingerprint, 'failed',
                          'error' => reason, 'summary' => summary, 'run_pid' => nil)
      log "#{fingerprint}: failed - #{reason}"
      :failed
    end

    def commit_count(branch)
      out, = git('log', '--oneline', "#{@config.dig('dispatch', 'base_ref')}..#{branch}")
      out.split("\n").count { |line| !line.empty? }
    end

    def changed_files(branch)
      out, = git('diff', '--name-only', "#{@config.dig('dispatch', 'base_ref')}...#{branch}")
      out.split("\n").map(&:strip).reject(&:empty?)
    end

    def find_rca_doc(worktree, fingerprint)
      path = Dir[File.join(worktree, 'docs', 'incidents', "*#{fingerprint}*")].first
      path&.sub("#{worktree}/", '')
    end

    # --- publishing --------------------------------------------------------------------

    # Push the branch and open a draft PR with the RCA as the body.
    #
    # Everything here runs from the main checkout, not from the incident's worktree. A
    # worktree is disposable - it may have been removed long before you decide the fix is
    # worth publishing - but the branch and its objects live in the shared repository, so
    # this keeps working regardless.
    #
    # Never fatal to the incident: if the remote is unreachable or `gh` is not authenticated,
    # the branch and the RCA are still on disk and still valuable; we record why publishing
    # failed rather than throwing that away.
    def publish(fingerprint, branch, rca_doc, force: false)
      # Automatic publishing is opt-in via config; `force` is the dashboard/CLI saying
      # "yes, publish this one" after a human has approved the RCA.
      return {} unless force || @config.dig('dispatch', 'open_pull_request')

      # An existing PR means this is a re-run; do not try to create a second one.
      if (existing = find_pull_request(branch))
        return { 'pr_url' => existing['url'], 'pr_number' => existing['number'] }
      end

      out, status = git('push', '--set-upstream', 'origin', branch)
      return { 'pr_error' => "push failed: #{out.lines.last.to_s.strip}" } unless status.success?

      log "#{fingerprint}: pushed #{branch}"

      incident = @store.find(fingerprint) || {}
      title = "Fix #{incident['exception_class']} in #{incident['location'] || 'background'} " \
              "(incident #{fingerprint})"
      # PR base is the configured base ref without its remote prefix (origin/main -> main).
      base = @config.dig('dispatch', 'base_ref').to_s.delete_prefix('origin/')

      args = ['gh', 'pr', 'create', '--draft', '--base', base, '--head', branch, '--title', title]
      body_file = rca_body_file(branch, rca_doc)
      args += if body_file
                ['--body-file', body_file.path]
              else
                ['--body', "Automated RCA for incident `#{fingerprint}`. See the commit message."]
              end

      out, status = Open3.capture2e(*args, chdir: @repo_root)
      body_file&.unlink
      return { 'pr_error' => "gh pr create failed: #{out.lines.last.to_s.strip}" } unless status.success?

      url = out[%r{https://\S+/pull/\d+}]
      log "#{fingerprint}: opened draft PR #{url}"
      { 'pr_url' => url, 'pr_number' => url&.slice(%r{/pull/(\d+)}, 1)&.to_i }
    rescue StandardError => e
      { 'pr_error' => "#{e.class}: #{e.message}" }
    end

    # Read the RCA off the branch into a temp file for `gh --body-file`. Reading from the
    # branch rather than from a worktree path is what makes publishing work after the
    # worktree is gone.
    def rca_body_file(branch, rca_doc)
      return nil if rca_doc.to_s.empty?

      out, status = Open3.capture2e('git', '-C', @repo_root, 'show', "#{branch}:#{rca_doc}")
      return nil unless status.success?

      file = Tempfile.new(['rca', '.md'])
      file.write(out)
      file.flush
      file
    end

    def find_pull_request(branch)
      out, status = Open3.capture2e('gh', 'pr', 'list', '--head', branch, '--state', 'all',
                                    '--json', 'number,url', chdir: @repo_root)
      return nil unless status.success?

      JSON.parse(out).first
    rescue StandardError
      nil
    end

    # --output-format json wraps the final assistant message in a envelope; fall back to
    # the raw tail if the run died before emitting valid JSON.
    def extract_summary(output)
      parsed = JSON.parse(output)
      parsed['result'] || parsed['error']
    rescue JSON::ParserError
      output.to_s.strip[-2000..] || output.to_s.strip
    end

    def log(message)
      @logger&.call("[dispatch] #{message}")
    end
  end
end
