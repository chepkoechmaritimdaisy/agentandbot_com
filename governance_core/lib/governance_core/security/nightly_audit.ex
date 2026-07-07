defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Performs nightly security audits on agent traffic logs to produce summaries
  following the "Decompiler Standard".
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:run_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      summary = parse_to_decompiler_standard(content)

      report_path = Path.join(File.cwd!(), "priv/nightly_audit_report.txt")
      File.write!(report_path, summary)
      Logger.info("Nightly Audit completed. Report saved to #{report_path}")
    else
      Logger.warning("Audit log path does not exist: #{log_path}")
    end
  end

  defp parse_to_decompiler_standard(content) do
    lines = String.split(content, "\n", trim: true)

    critical_logs = Enum.filter(lines, fn line ->
      String.contains?(line, "CRITICAL") or
      String.contains?(line, "ERROR") or
      String.contains?(line, "DENIED")
    end)

    """
    [DECOMPILER STANDARD AUDIT REPORT]
    DATE: #{Date.utc_today()}
    STATUS: #{if length(critical_logs) > 0, do: "ATTENTION_REQUIRED", else: "CLEAN"}

    [TRAFFIC_SNIPPET]
    #{Enum.join(Enum.take(critical_logs, 20), "\n")}

    [SUMMARY]
    Total Critical Events: #{length(critical_logs)}
    """
  end
end
