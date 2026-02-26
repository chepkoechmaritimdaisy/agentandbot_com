defmodule GovernanceCore.SecurityAuditTest do
  use ExUnit.Case
  alias GovernanceCore.SecurityAudit
  alias GovernanceCore.Protocols.ClawSpeak

  test "perform_audit detects large payloads and restricted opcodes" do
    # Create a large payload event
    large_arg = String.duplicate("A", 2000)
    large_frame = %ClawSpeak{from: 1, to: 2, op: 0x10, arg: large_arg}

    large_event = %{
      timestamp: DateTime.utc_now(),
      raw: <<>>, # Raw doesn't matter for this test as we test the decoded part
      decoded: {:ok, large_frame, <<>>}
    }

    # Create a restricted opcode event
    restricted_frame = %ClawSpeak{from: 3, to: 4, op: 0xFF, arg: "test"}
    restricted_event = %{
      timestamp: DateTime.utc_now(),
      raw: <<>>,
      decoded: {:ok, restricted_frame, <<>>}
    }

    # Create a normal event
    normal_frame = %ClawSpeak{from: 5, to: 6, op: 0x10, arg: "ok"}
    normal_event = %{
      timestamp: DateTime.utc_now(),
      raw: <<>>,
      decoded: {:ok, normal_frame, <<>>}
    }

    events = [large_event, restricted_event, normal_event]

    # We capture logs to verify the output since perform_audit returns :ok and logs warnings
    # In a real test we would use ExUnit.CaptureLog
    import ExUnit.CaptureLog

    log = capture_log(fn ->
      SecurityAudit.perform_audit(events)
    end)

    assert log =~ "Large Payload Detected"
    assert log =~ "Restricted Opcode 0xFF"
    refute log =~ "Agent 5" # Normal event shouldn't trigger a warning
  end
end
