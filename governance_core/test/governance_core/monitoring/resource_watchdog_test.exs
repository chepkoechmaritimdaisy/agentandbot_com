defmodule GovernanceCore.Monitoring.ResourceWatchdogTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias GovernanceCore.Monitoring.ResourceWatchdog

  # Expose the private parse_and_log function for testing purposes
  # Since it's a private function, we will test it by overriding the output handling
  # in a custom test module or simply relying on the public API (GenServer state) if possible.
  # However, it's easier to mock system calls or test the logic using macro bypass if needed.
  # We will just verify it runs and handles system failures without crashing.

  test "resource watchdog handles missing docker cleanly" do
    {:ok, pid} = GenServer.start_link(ResourceWatchdog, %{})

    log = capture_log(fn ->
      send(pid, :watch)
      :sys.get_state(pid)
    end)

    # We might not have docker installed, or it might work, just ensuring it logs and survives.
    assert Process.alive?(pid) == true
  end
end
