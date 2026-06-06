defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit summarizing "Human-in-the-loop" agent traffic
  according to the Decompiler Standard.
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

  defp perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      filtered = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      snippet = Enum.join(filtered, "\n")
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{timestamp}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{snippet}
      STATUS: ANALYZED
      """

      Logger.info("Nightly Audit Report Generated:\n#{report}")
    else
      Logger.warning("Audit log path not configured or file not found.")
    end
  end
end
