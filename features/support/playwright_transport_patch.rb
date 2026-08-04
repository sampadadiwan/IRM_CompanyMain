# Workarounds for hangs in playwright-ruby-client 1.52+ /
# capybara-playwright-driver when the `node playwright run-driver` process
# wedges (stops replying) during a long run.
#
# ROOT CAUSE (confirmed on a hung parallel run, July 2026): playwright
# enforces per-action timeouts in the DRIVER, not the Ruby client. Every
# synchronous protocol call funnels through
# Connection#send_message_to_server, which waits on a future with NO
# timeout. If the driver wedges mid-run, the worker hangs forever inside
# whatever scenario step it was on (killing the wedged driver instantly
# "unstuck" the hung worker, which then finished and exited normally).
# The shutdown path has the same unbounded waits:
#
# The at_exit hook capybara-playwright-driver installs runs:
#   quit -> @playwright_browser&.close -> @browser_runner.stop -> Transport#stop
# and each of the first two steps can hang forever:
#
# 1. `browser.close` is a protocol call: Connection#send_message_to_server
#    does `.value!` on a future with NO timeout, waiting for the node
#    driver to reply. A wedged driver (seen after long parallel runs)
#    never replies, so the worker sleeps on that futex forever — before
#    Transport#stop is ever reached.
#
# 2. Transport#stop used to `@thread&.terminate` (1.50.1), but now does an
#    unbounded `@thread&.join`, waiting for the `node playwright run-driver`
#    process to exit on its own after its stdio is closed.
#
# Both waits are bounded here: give each step a few seconds, then fall
# through / hard-kill the driver's process group (the driver is spawned
# with `pgroup: true`, so `-pid` reliably takes out the driver and any
# browser children it still owns).
#
# Remove this file once upstream fixes the unbounded waits
# (https://github.com/YusukeIwaki/playwright-ruby-client — check releases
# after 1.61.0).
require 'timeout'
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

# Raised when the node driver fails to answer a protocol call in time —
# distinct from Playwright::TimeoutError so it can't be confused with a
# normal driver-side action timeout.
module Playwright
  class DriverUnresponsiveError < StandardError; end
end

# THE PRIMARY FIX: bound every synchronous protocol call client-side.
# A wedged driver now fails the current scenario with a clear error
# instead of hanging the cucumber worker forever.
module Playwright
  class Connection
    # Generous: legitimate calls finish in ms; driver-side action timeouts
    # (default 30s) cap slow navigations well below this.
    PROTOCOL_CALL_TIMEOUT = Integer(ENV.fetch('PLAYWRIGHT_PROTOCOL_CALL_TIMEOUT', 120))

    def send_message_to_server(guid, method, params, metadata: nil)
      future = async_send_message_to_server(guid, method, params, metadata: metadata)
      # async_ returns nil when the connection is already closed.
      raise (@closed_error || DriverUnresponsiveError.new('connection closed')) if future.nil?

      # wait(timeout) returns false on timeout without consuming the future.
      unless future.wait(PROTOCOL_CALL_TIMEOUT)
        raise DriverUnresponsiveError,
              "playwright driver did not answer '#{method}' within #{PROTOCOL_CALL_TIMEOUT}s — driver wedged?"
      end
      future.value!
    end
  end
end

# Reject pending protocol calls when the driver dies. Upstream only fires
# @on_driver_closed on IOError; a clean EOF (driver killed / exited) just
# ends the read loop silently, leaving every waiting future unresolved
# forever. This mirrors upstream handle_stdout plus the EOF callback.
module Playwright
  class Transport
    private def handle_stdout(packet_size: 32_768)
      while chunk = @stdout.read(4)
        length = chunk.unpack1('V') # unsigned 32bit, little endian
        buffer = StringIO.new
        (length / packet_size).to_i.times do
          buffer << @stdout.read(packet_size)
        end
        buffer << @stdout.read(length % packet_size)
        buffer.rewind
        obj = JSON.parse(buffer.read)

        debug_recv_message(obj) if @debug
        @on_message&.call(obj)
      end
      # EOF: driver exited — reject pending calls via Connection#cleanup.
      @on_driver_closed&.call
    rescue IOError
      # disconnected by remote.
      @on_driver_closed&.call
    end
  end
end

# Bound the `browser.close` protocol call (hang #1 above). Prepended so
# `super` is never needed — we fully replace `quit`, but keep its shape:
# close the browser if the driver still responds, then ALWAYS stop the
# runner so the bounded Transport#stop above can reap the node process.
Capybara::Playwright::Driver.prepend(Module.new do
  # Seconds to allow the driver to acknowledge browser.close.
  QUIT_CLOSE_TIMEOUT = 15

  private def quit
    # Timeout.timeout interrupts the futex wait inside
    # Connection#send_message_to_server's unbounded `.value!`.
    Timeout.timeout(QUIT_CLOSE_TIMEOUT) { @playwright_browser&.close }
  rescue Timeout::Error, StandardError
    # Driver unresponsive or connection already dead — fall through so
    # @browser_runner.stop can kill the driver's process group.
  ensure
    @playwright_browser = nil
    @browser_runner.stop
  end
end)

# ---------------------------------------------------------------------------
# Belt-and-braces: a run in July 2026 hung at shutdown even WITH the two
# bounds above (main thread parked on a futex, node driver and its stdio
# reader threads all still alive — i.e. it never reached Transport#stop,
# and the Timeout in `quit` never fired). Root wait location unknown, so:
#
# 1. Preemptively SIGKILL the node driver's process group at exit, BEFORE
#    the driver gem's at_exit runs. All scenarios are finished by then, so
#    nothing needs the browser; with the driver dead, every subsequent
#    protocol call fails fast (EPIPE / driver-closed) instead of waiting
#    forever on a reply that will never come.
# 2. Arm a watchdog thread that, if shutdown STILL takes >60s, dumps every
#    thread's backtrace to tmp/ (so the next hang diagnoses itself) and
#    force-exits with cucumber's intended exit status.
#
# Registered from an After hook because at_exit hooks run LIFO: the driver
# gem registers its at_exit while the first scenario creates the browser,
# so a hook registered AFTER that (first After) runs BEFORE the driver's.
# `respond_to?` guard keeps this file loadable outside cucumber.
# ---------------------------------------------------------------------------
if respond_to?(:After, true)
  shutdown_guard_installed = false
  After do
    next if shutdown_guard_installed
    shutdown_guard_installed = true

    at_exit do
      # Kernel#exit raises SystemExit, so during at_exit processing $! holds
      # cucumber's intended exit status — preserve it for the watchdog.
      status = $!.is_a?(SystemExit) ? $!.status : 0

      watchdog = Thread.new do
        sleep 60
        begin
          File.open("tmp/cucumber_shutdown_hang_#{Process.pid}.log", 'w') do |f|
            f.puts "Shutdown exceeded 60s at #{Time.now}; thread backtraces:"
            Thread.list.each do |t|
              f.puts "--- #{t.inspect} name=#{t.name.inspect}"
              f.puts((t.backtrace || ['<no backtrace>']).join("\n"))
              f.puts
            end
          end
        rescue StandardError
          nil # never let the watchdog itself raise
        end
        Process.exit!(status)
      end
      watchdog.report_on_exception = false

      # Preemptive kill: the driver is spawned with `pgroup: true`, so its
      # pid doubles as its pgid and `-pid` takes out driver + browsers.
      begin
        `pgrep -P #{Process.pid} -f 'playwright run-driver'`.split.each do |pid|
          Process.kill(:KILL, -pid.to_i)
        rescue Errno::ESRCH, Errno::EPERM
          nil # already gone
        end
      rescue StandardError
        nil # pgrep missing/failed — watchdog still protects us
      end
    end
  end
end
