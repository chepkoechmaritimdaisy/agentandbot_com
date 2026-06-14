defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit on "Human-in-the-loop" agent traffic logs
  and summarizes critical findings according to the Decompiler Standard.
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
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      critical_lines =
        File.stream!(log_path)
        |> Stream.filter(fn line ->
          String.contains?(line, "CRITICAL") or
          String.contains?(line, "ERROR") or
          String.contains?(line, "DENIED")
        end)
        |> Enum.to_list()

      if length(critical_lines) > 0 do
        snippet = Enum.join(critical_lines, "\n")
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

        report = """
        --- DECOMPILER STANDARD AUDIT ---
        TIMESTAMP: #{timestamp}
        SOURCE: HUMAN_IN_THE_LOOP
        TRAFFIC_SNIPPET:
        #{snippet}
        STATUS: ANALYZED
        ---------------------------------
        """

        Logger.info("Nightly Security Audit Report Generated:\n#{report}")
      else
        Logger.info("Nightly Security Audit: No critical traffic findings.")
      end
    else
      Logger.warning("Nightly Security Audit: Log path not configured or file does not exist.")
    end
  end
end
