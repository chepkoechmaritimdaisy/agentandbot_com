defmodule GovernanceCore.Monitoring.SecurityAuditTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  setup do
    log_path = Path.join(System.tmp_dir!(), "test_audit.log")
    Application.put_env(:governance_core, :audit_log_path, log_path)

    File.write!(log_path, "")

    on_exit(fn ->
      File.rm(log_path)
      Application.delete_env(:governance_core, :audit_log_path)
    end)

    %{log_path: log_path}
  end

  test "perform_audit parses logs lazily and formats decompiler standard", %{log_path: log_path} do
    File.write!(log_path, "NORMAL traffic\nCRITICAL unauthorized access\nAnother NORMAL line\nERROR missing token\n")

    state = %{last_byte_pos: 0}

    log = capture_log(fn ->
      new_state = GovernanceCore.Monitoring.SecurityAudit.perform_audit(state)
      assert new_state.last_byte_pos > 0
    end)

    assert log =~ "--- DECOMPILER STANDARD AUDIT ---"
    assert log =~ "CRITICAL unauthorized access"
    assert log =~ "ERROR missing token"
    refute log =~ "NORMAL traffic"
  end

  test "perform_audit handles log rotation/truncation", %{log_path: log_path} do
    File.write!(log_path, "DENIED test\n")
    state = %{last_byte_pos: 100} # Larger than the current file size

    log = capture_log(fn ->
      new_state = GovernanceCore.Monitoring.SecurityAudit.perform_audit(state)
      assert new_state.last_byte_pos == File.stat!(log_path).size
    end)

    assert log =~ "DENIED test"
  end
end
