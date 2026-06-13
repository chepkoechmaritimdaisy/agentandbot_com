defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Analyzes 'Human-in-the-loop' agent traffic from audit logs every night.
  Filters for critical findings (CRITICAL, ERROR, DENIED) and formats using the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      analyze_and_report(content)
    else
      Logger.warning("NightlyAudit: Audit log file not found at #{log_path}")
    end
  end

  defp analyze_and_report(content) do
    lines = String.split(content, "\n", trim: true)

    # Filter for critical findings
    critical_snippets =
      lines
      |> Enum.filter(fn line ->
        String.contains?(line, "CRITICAL") or
          String.contains?(line, "ERROR") or
          String.contains?(line, "DENIED")
      end)
      |> Enum.join("\n")

    if critical_snippets != "" do
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{timestamp}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{critical_snippets}

      STATUS: ANALYZED
      """

      # We can write this summary out or just log it so it is visible in the morning.
      Logger.info("NightlyAudit Report Generated:\n#{report}")

      # Optionally, write to a report file
      report_path = Application.get_env(:governance_core, :audit_report_path, "priv/agent_report.md")
      case File.write(report_path, report, [:append]) do
        :ok -> :ok
        {:error, reason} -> Logger.error("Failed to write audit report: #{inspect(reason)}")
      end
    else
      Logger.info("NightlyAudit: No critical findings in the audit log tonight.")
    end
  end
end
