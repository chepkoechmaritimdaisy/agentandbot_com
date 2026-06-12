defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit to format "Human-in-the-loop" traffic
  according to the Decompiler Standard.
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
    perform_nightly_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_nightly_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/agent_traffic.log"

    case File.read(log_path) do
      {:ok, content} ->
        analyze_logs(content)
      {:error, :enoent} ->
        Logger.info("No audit logs found at #{log_path}. Skipping.")
      {:error, reason} ->
        Logger.error("Failed to read audit logs at #{log_path}: #{inspect(reason)}")
    end
  end

  defp analyze_logs(content) do
    lines = String.split(content, "\n", trim: true)

    # Filter for critical keywords
    critical_lines = Enum.filter(lines, fn line ->
      String.match?(line, ~r/(CRITICAL|ERROR|DENIED)/i)
    end)

    if Enum.empty?(critical_lines) do
      Logger.info("Nightly Security Audit completed. No critical issues found.")
    else
      report = build_decompiler_report(critical_lines)
      Logger.warning("Nightly Security Audit Findings:\n#{report}")
    end
  end

  defp build_decompiler_report(critical_lines) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(critical_lines, "\n")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
