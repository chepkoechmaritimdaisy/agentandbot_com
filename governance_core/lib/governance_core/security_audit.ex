defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Streams human-in-the-loop agent traffic directly from log/agent_traffic.log
  and logs a summary (compliant with the Decompiler Standard).
  """
  use GenServer
  require Logger

  # Default interval: 24 hours
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
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    log_path = "log/agent_traffic.log"

    if File.exists?(log_path) do
      # Stream the log file
      critical_entries =
        File.stream!(log_path)
        |> Stream.filter(&String.contains?(&1, "Human-in-the-loop"))
        |> Enum.to_list()

      count = length(critical_entries)

      if count > 0 do
        Logger.warning("Security Audit Summary: #{count} 'Human-in-the-loop' entries detected. Review required.")
        # E.g., print top 5 critical items
        critical_entries
        |> Enum.take(5)
        |> Enum.each(&Logger.warning("  Critical Entry: #{String.trim(&1)}"))
      else
        Logger.info("Security Audit Summary: No critical 'Human-in-the-loop' entries found.")
      end
    else
      Logger.error("Security Audit Failed: #{log_path} not found.")
    end
  end
end
