defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Nightly Security Audit GenServer.
  Analyzes human-in-the-loop agent traffic logs and summarizes
  them according to the Decompiler Standard, highlighting critical warnings.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:run_audit, state) do
    run_nightly_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  defp run_nightly_audit do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_findings =
        lines
        |> Enum.filter(fn line ->
          String.contains?(line, "CRITICAL") or
            String.contains?(line, "ERROR") or
            String.contains?(line, "DENIED")
        end)

      report = """
      === DECOMPILER STANDARD AUDIT REPORT ===
      Total Logs Processed: #{length(lines)}
      Critical Findings: #{length(critical_findings)}

      TRAFFIC_SNIPPET:
      #{Enum.join(Enum.take(critical_findings, 10), "\n")}
      ========================================
      """

      if length(critical_findings) > 0 do
        Logger.warning("Nightly Audit found issues:\n#{report}")
      else
        Logger.info("Nightly Audit completed cleanly. No critical findings.")
      end
    else
      Logger.debug("Nightly Audit skipped: Audit log file not found or not configured.")
    end
  end
end
