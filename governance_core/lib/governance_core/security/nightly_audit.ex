defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Performs nightly analysis of Human-in-the-loop agent traffic logs,
  summarizing critical findings according to the Decompiler Standard.
  """
  use GenServer
  require Logger

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
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)

      lines = String.split(content, "\n")

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Audit completed. No critical findings.")
      else
        snippet = Enum.join(critical_lines, "\n")
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

        report = """
        --- DECOMPILER STANDARD AUDIT ---
        TIMESTAMP: #{timestamp}
        SOURCE: HUMAN_IN_THE_LOOP
        TRAFFIC_SNIPPET:
        #{snippet}
        STATUS: ANALYZED
        """

        Logger.warning("Nightly Audit Critical Findings:\n#{report}")
      end
    else
      Logger.info("Nightly Audit skipped: Audit log path not configured or file missing.")
    end
  end
end
