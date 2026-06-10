defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Processes 'Human-in-the-loop' agent traffic logs every night
  and outputs a summary according to the Decompiler Standard.
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
  def handle_info(:nightly_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :nightly_audit, @interval)
  end

  def perform_audit do
    Logger.info("NightlyAudit: Starting background log analysis...")

    # Configure path dynamically from app env to avoid hardcoding
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      analyze_logs(log_path)
    else
      Logger.warning("NightlyAudit: Audit log file not found at #{log_path}")
    end
  end

  defp analyze_logs(log_path) do
    content = File.read!(log_path)
    lines = String.split(content, "\n", trim: true)

    # Filter for critical findings
    critical_findings =
      Enum.filter(lines, fn line ->
        upcase_line = String.upcase(line)
        String.contains?(upcase_line, "CRITICAL") ||
          String.contains?(upcase_line, "ERROR") ||
          String.contains?(upcase_line, "DENIED")
      end)

    if Enum.empty?(critical_findings) do
      Logger.info("NightlyAudit: No critical findings in traffic logs.")
    else
      snippet = Enum.join(critical_findings, "\n")
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      # Format to Decompiler Standard
      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{timestamp}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{snippet}
      STATUS: ANALYZED
      """

      Logger.info("NightlyAudit: \n#{report}")
    end
  end
end
