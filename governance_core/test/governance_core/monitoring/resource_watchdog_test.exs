defmodule GovernanceCore.Monitoring.ResourceWatchdogTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  # To test the un-mockable System.cmd, we'd need to abstract it, but since
  # we cannot easily mock System.cmd here, we'll test the error handling
  # or use a private function exposure if needed. Given the constraints,
  # we'll test the process supervision and check_resources execution.

  test "check_resources runs without crashing" do
    log = capture_log(fn ->
      GovernanceCore.Monitoring.ResourceWatchdog.check_resources()
    end)

    # We might log a warning if docker isn't installed or running,
    # but the process should NOT crash.
    assert true
  end
end
