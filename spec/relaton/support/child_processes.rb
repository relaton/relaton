require "fileutils"
require "rbconfig"
require "timeout"
require "tmpdir"

# Run Ruby scripts in fresh processes at the same time. `Process.spawn`, not
# `fork`, so the specs also run where `fork` is missing (Windows), and the
# children get none of the parent's loaded code or RSpec stubs: a script sets
# up what it needs. A child inherits this process's $LOAD_PATH and working
# directory. Each script is a file, which keeps the command line short.
#
# A spawned child loads its code for seconds, and its real work can be much
# shorter, so the children would run one after the other. A script therefore
# calls `start_barrier!` after its requires: it waits there until every child
# is ready, and then all of them start their work together.
module ChildProcesses
  PRELUDE = <<~RUBY.freeze
    def start_barrier!
      File.write File.join(CHILD_TMP, "ready\#{CHILD_INDEX}"), ""
      sleep 0.01 until File.exist? File.join(CHILD_TMP, "go")
    end
  RUBY

  # @param bodies [Array<String>] one Ruby script for each child; each one
  #   calls `start_barrier!` once its code is loaded
  # @param timeout [Integer] seconds to wait for all the children
  # @return [Array(Array<Process::Status>, Array<String>)] the exit statuses
  #   and the stdout+stderr of each child
  def run_children(bodies, timeout: 180)
    Dir.mktmpdir do |tmp|
      pids = bodies.each_with_index.map { |body, i| spawn_child tmp, i, body }
      statuses = wait_all tmp, pids, timeout
      [statuses, child_logs(tmp, bodies.size)]
    end
  end

  private

  def spawn_child(tmp, index, body)
    script = File.join tmp, "child#{index}.rb"
    File.write script, <<~RUBY
      $LOAD_PATH.replace(#{$LOAD_PATH.inspect})
      CHILD_TMP = #{tmp.inspect}
      CHILD_INDEX = #{index}
      #{PRELUDE}
      #{body}
    RUBY
    Process.spawn RbConfig.ruby, script, %i[out err] => child_log(tmp, index)
  end

  # Start the children together once all of them are ready, then wait for
  # them. A child that ends before it is ready (an error) also lets the
  # others go. On a timeout, kill the children and raise with their logs.
  def wait_all(tmp, pids, timeout)
    statuses = {}
    Timeout.timeout(timeout) do
      sleep 0.01 until all_ready?(tmp, pids, statuses)
      FileUtils.touch File.join(tmp, "go")
      wait_rest pids, statuses
    end
  rescue Timeout::Error
    stop pids
    raise Timeout::Error, "timed out:\n#{child_logs(tmp, pids.size).join}"
  end

  # Every child is ready or has ended. Collects the status of an ended child.
  def all_ready?(tmp, pids, statuses)
    pids.each_with_index.all? do |pid, i|
      statuses[i] ||= Process.wait2(pid, Process::WNOHANG)&.last
      statuses[i] || File.exist?(File.join(tmp, "ready#{i}"))
    end
  end

  def wait_rest(pids, statuses)
    pids.each_index.map { statuses[_1] ||= Process.wait2(pids[_1]).last }
  end

  def stop(pids)
    pids.each do |pid|
      Process.kill :KILL, pid
      Process.wait pid
    rescue Errno::ESRCH, Errno::ECHILD
      next
    end
  end

  def child_log(tmp, index)
    File.join tmp, "child#{index}.log"
  end

  def child_logs(tmp, count)
    Array.new(count) { File.read child_log(tmp, _1) }
  end
end

RSpec.configure { |config| config.include ChildProcesses }
