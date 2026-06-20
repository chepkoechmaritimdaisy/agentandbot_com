defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that analyzes "Human-in-the-loop" agent traffic every night and
  summarizes it according to the project's 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_audit()
    {:ok, %{}}
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
      analyze_and_report(content)
    else
      Logger.info("NightlyAudit: Audit log file not found at #{log_path}, skipping.")
    end
  end

  defp analyze_and_report(content) do
    critical_logs =
      content
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)
      |> Enum.join("\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{if critical_logs == "", do: "No critical findings.", else: critical_logs}
    STATUS: ANALYZED
    """

    Logger.info("NightlyAudit generated report:\n#{report}")
  end
end
