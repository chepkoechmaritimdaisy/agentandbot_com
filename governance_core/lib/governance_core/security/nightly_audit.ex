defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Processes human-in-the-loop agent traffic nightly and formats it
  into the Decompiler Standard summary.
  """
  use GenServer
  require Logger

  # Interval: 24 hours
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
    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_logs = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED")
      end)

      snippet = Enum.join(critical_logs, "\n")

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_string()}
      SOURCE: HUMAN_IN_THE_LOOP
      STATUS: ANALYZED

      TRAFFIC_SNIPPET:
      #{if snippet == "", do: "No critical findings.", else: snippet}
      ----------------------------------
      """

      Logger.info("Nightly Audit Report Generated:\n#{report}")
    else
      Logger.warning("NightlyAudit: Traffic log file not found at #{log_path}")
    end
  end
end
