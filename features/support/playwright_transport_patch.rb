# Workaround for a shutdown hang introduced in playwright-ruby-client 1.52+.
#
# Transport#stop used to `@thread&.terminate` (1.50.1), but now does an
# unbounded `@thread&.join`, waiting for the `node playwright run-driver`
# process to exit on its own. When the driver doesn't exit after its stdio
# is closed, every cucumber worker hangs forever in the at_exit hook that
# capybara-playwright-driver installs (browser close -> execution.stop ->
# Transport#stop), which is exactly what stalls parallel cucumber at the
# end of a run.
#
# This patch bounds the wait: give the driver a few seconds to exit
# gracefully, then hard-kill its process group (the driver is spawned with
# `pgroup: true`, so `-pid` reliably takes out the driver and any browser
# children it still owns).
#
# Remove this file once upstream fixes the unbounded join
# (https://github.com/YusukeIwaki/playwright-ruby-client — check releases
# after 1.61.0).
module Playwright
  class Transport
    # Seconds to allow the node driver to exit cleanly before killing it.
    GRACEFUL_STOP_TIMEOUT = 10

    def stop
      # Same as upstream: closing stdio signals the driver to shut down.
      [@stdin, @stdout, @stderr].each { |io| io.close unless io.closed? }

      # @thread is the Open3 wait thread (Process::Waiter) for the driver.
      return if @thread.nil? || @thread.join(GRACEFUL_STOP_TIMEOUT)

      # Driver didn't exit in time — kill its whole process group so no
      # orphaned `node run-driver` or browser processes are left behind.
      begin
        Process.kill(:KILL, -@thread.pid)
      rescue Errno::ESRCH, Errno::EPERM
        # Process group already gone — nothing to clean up.
      end
      @thread.join(2)
    end
  end
end
