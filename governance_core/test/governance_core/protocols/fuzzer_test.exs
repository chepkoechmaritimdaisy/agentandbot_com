defmodule GovernanceCore.Protocols.FuzzerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  test "fuzz_parser cleanly catches errors" do
    # Capture log ensures we don't crash and we actually log the caught errors
    log = capture_log(fn ->
      GovernanceCore.Protocols.Fuzzer.fuzz_parser()
    end)

    # Some randomized payloads are bound to fail since they are purely random bytes
    assert log =~ "Fuzzer caught exception from parser"
  end
end
