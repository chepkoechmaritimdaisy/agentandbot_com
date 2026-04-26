defmodule GovernanceCore.Monitoring.SecurityAuditTest do
  use ExUnit.Case, async: false
  alias GovernanceCore.Monitoring.SecurityAudit

  setup do
    priv_dir = Path.join(File.cwd!(), "priv")
    log_file = Path.join(priv_dir, "agent_traffic.log")
    report_file = Path.join(priv_dir, "security_audit_report.txt")

    File.mkdir_p!(priv_dir)

    # Pre-populate some logs
    log_data = """
    INFO: All good here
    CRITICAL: Unauthorized access attempt detected!
    DEBUG: Fetching new user settings
    ERROR: Failed to connect to db
    DENIED: Access restricted to human
    """
    File.write!(log_file, log_data)

    on_exit(fn ->
      File.rm(log_file)
      File.rm(report_file)
    end)

    {:ok, report_file: report_file}
  end

  test "security audit correctly filters CRITICAL, ERROR, DENIED and builds Decompiler Standard report", %{report_file: report_file} do
    {:ok, pid} = GenServer.start_link(SecurityAudit, %{last_byte_pos: 0})

    send(pid, :audit)
    :sys.get_state(pid)

    assert File.exists?(report_file)

    content = File.read!(report_file)

    assert String.contains?(content, "--- DECOMPILER STANDARD AUDIT ---")
    assert String.contains?(content, "TIMESTAMP:")
    assert String.contains?(content, "SOURCE: HUMAN_IN_THE_LOOP")
    assert String.contains?(content, "STATUS: ANALYZED")

    assert String.contains?(content, "CRITICAL: Unauthorized access attempt detected!")
    assert String.contains?(content, "ERROR: Failed to connect to db")
    assert String.contains?(content, "DENIED: Access restricted to human")
    refute String.contains?(content, "INFO: All good here")
  end
end
