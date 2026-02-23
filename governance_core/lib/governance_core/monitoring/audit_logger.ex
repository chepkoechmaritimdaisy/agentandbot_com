defmodule GovernanceCore.Monitoring.AuditLogger do
  require Logger

  @moduledoc """
  Handles the automated auditing of agent traffic, specifically focusing on
  "Human-in-the-loop" interactions. Generates nightly summaries.
  """

  @doc """
  Analyzes daily traffic and generates a "Decompiler Standard" summary.
  Intended to be run by a nightly cron job (e.g., Oban).
  """
  def analyze_daily_traffic do
    Logger.info("Starting Daily Audit Log Analysis...")

    # Fetch logs from configured source (or return empty if not configured)
    logs = fetch_logs()

    critical_events = Enum.filter(logs, fn log -> log.level == :critical end)
    human_interactions = Enum.filter(logs, fn log -> log.type == :human_approval end)

    summary = generate_summary(critical_events, human_interactions)

    # In production, this would be emailed or posted to a dashboard
    Logger.info("\n=== DAILY AUDIT SUMMARY ===\n" <> summary)

    {:ok, summary}
  end

  defp fetch_logs do
    case Application.get_env(:governance_core, :audit_log_source) do
      nil ->
        Logger.debug("AuditLogger: No log source configured.")
        []

      _source ->
        # Placeholder for actual log fetching implementation
        []
    end
  end

  defp generate_summary(critical, human) do
    """
    Date: #{Date.utc_today()}
    Total Critical Events: #{length(critical)}
    Total Human Approvals: #{length(human)}

    -- Critical Alerts --
    #{format_logs(critical)}

    -- Human-in-the-Loop Actions --
    #{format_logs(human)}
    """
  end

  defp format_logs(logs) do
    logs
    |> Enum.map(fn log -> "- [#{log.timestamp}] #{log.message}" end)
    |> Enum.join("\n")
  end
end
