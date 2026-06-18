defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Processes "Human-in-the-loop" agent traffic logs nightly,
  summarizing critical warnings according to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:run_nightly_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_nightly_audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)

      critical_lines =
        content
        |> String.split("\n", trim: true)
        |> Enum.filter(fn line ->
             String.contains?(line, "CRITICAL") or
             String.contains?(line, "ERROR") or
             String.contains?(line, "DENIED")
           end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Audit complete: No critical traffic findings.")
      else
        snippet = Enum.join(critical_lines, "\n")
        report = generate_decompiler_report(snippet)
        Logger.warning("Nightly Audit Generated Findings:\n#{report}")
      end
    else
      Logger.info("Nightly Audit skipped: Log file #{log_path} not found.")
    end
  end

  defp generate_decompiler_report(snippet) do
    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    ---------------------------------
    """
  end
end
