defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit on the "Human-in-the-loop" agent traffic logs.
  Formats critical findings according to the Decompiler Standard.
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
  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/default_agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      analyze_logs(content)
    else
      Logger.warn("Audit log file not found at: #{log_path}")
    end
  end

  defp analyze_logs(content) do
    lines = String.split(content, "\n", trim: true)

    # Filter for critical keywords
    critical_logs = Enum.filter(lines, fn line ->
      String.contains?(line, "CRITICAL") or
      String.contains?(line, "ERROR") or
      String.contains?(line, "DENIED")
    end)

    if Enum.empty?(critical_logs) do
      Logger.info("Nightly Security Audit: No critical findings.")
    else
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      snippet = Enum.join(Enum.take(critical_logs, 10), "\n")

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{timestamp}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{snippet}
      STATUS: ANALYZED
      """

      Logger.warn("Nightly Security Audit Findings:\n#{report}")
    end
  end
end
