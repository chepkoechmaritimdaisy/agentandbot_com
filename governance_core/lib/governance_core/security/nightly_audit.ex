defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A nightly background job that reads traffic logs of 'Human-in-the-loop' interactions.
  Formats critical alerts (CRITICAL, ERROR, DENIED) according to the 'Decompiler Standard'.
  """

  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

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
    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join([File.cwd!(), "priv", "agent_traffic.log"])

    if File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_logs = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED")
      end)

      if not Enum.empty?(critical_logs) do
        summary = format_decompiler_standard(critical_logs)
        Logger.warning("Nightly Audit found critical issues:\n#{summary}")
      else
        Logger.info("Nightly Audit: No critical issues found.")
      end
    else
      Logger.debug("Nightly Audit: Log file not found at #{log_path}, skipping.")
    end
  end

  defp format_decompiler_standard(logs) do
    snippet = Enum.take(logs, 5) |> Enum.join("\n  ")
    """
    [DECOMPILER_STANDARD_AUDIT]
    STATUS: ALERTS_FOUND
    CRITICAL_COUNT: #{length(logs)}
    TRAFFIC_SNIPPET:
      #{snippet}
    """
  end
end
