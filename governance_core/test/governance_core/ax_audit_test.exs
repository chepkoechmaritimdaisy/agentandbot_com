defmodule GovernanceCore.AXAuditTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias GovernanceCore.AXAudit

  test "AX Audit runs handle_info and survives timeouts without crashing" do
    {:ok, pid} = GenServer.start_link(AXAudit, %{})

    log = capture_log(fn ->
      send(pid, :audit)
      :sys.get_state(pid)
    end)

    assert Process.alive?(pid) == true
    assert String.contains?(log, "Starting Continuous AX Audit on MCP endpoint...")
  end
end
