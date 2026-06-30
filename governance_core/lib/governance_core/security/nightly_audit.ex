defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Performs nightly security audits of "Human-in-the-loop" agent traffic,
  formatting output according to the Decompiler Standard `TRAFFIC_SNIPPET` format,
  filtering for critical findings like CRITICAL, ERROR, or DENIED.
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
    perform_nightly_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_nightly_audit do
    Logger.info("Starting Nightly Security Audit for Agent Traffic...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)

      critical_lines =
        content
        |> String.split("\n", trim: true)
        |> Enum.filter(fn line ->
          String.contains?(line, ["CRITICAL", "ERROR", "DENIED"])
        end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Audit completed: No critical findings in agent traffic.")
      else
        snippet = build_traffic_snippet(critical_lines)
        Logger.warning("Nightly Audit findings:\n#{snippet}")
      end
    else
      Logger.info("Nightly Audit skipped: Audit log file #{log_path} not found.")
    end
  end

  defp build_traffic_snippet(lines) do
    """
    BEGIN TRAFFIC_SNIPPET
    TIMESTAMP: #{DateTime.utc_now()}
    CRITICAL FINDINGS:
    #{Enum.join(lines, "\n")}
    END TRAFFIC_SNIPPET
    """
  end
end
