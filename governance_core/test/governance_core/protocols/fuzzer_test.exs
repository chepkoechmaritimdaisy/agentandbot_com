defmodule GovernanceCore.Protocols.FuzzerTest do
  use ExUnit.Case, async: true
  alias GovernanceCore.Protocols.Fuzzer

  test "fuzzer parses successfully without crashing process on invalid data" do
    # We trigger handle_info(:fuzz, state) directly to verify exceptions are correctly handled
    {:ok, pid} = GenServer.start_link(Fuzzer, %{})

    # Send a fuzz command to the GenServer
    send(pid, :fuzz)

    # Allow time to process and ensure process stays alive
    :sys.get_state(pid)

    assert Process.alive?(pid) == true
  end
end
