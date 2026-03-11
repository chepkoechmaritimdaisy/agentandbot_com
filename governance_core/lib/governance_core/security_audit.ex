defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  A GenServer that runs nightly to process human-in-the-loop agent traffic
  directly from the `log/agent_traffic.log` file using file streams.
  Analyzes it according to the "Decompiler Standard" and summarizes findings.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Schedule first run (we can do it immediately for testing or schedule it later)
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
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      # Process log file as stream
      results =
        @log_file
        |> File.stream!()
        |> Enum.reduce(%{total_processed: 0, critical_warnings: 0, anomalies: 0}, fn line, acc ->
          analyze_line(line, acc)
        end)

      # Summarize
      Logger.info("Nightly Security Audit Complete. Summary: #{inspect(results)}")

      if results.critical_warnings > 0 do
        Logger.error("CRITICAL ALERTS found during nightly audit! Please review traffic.")
      end
    else
      Logger.warning("Log file #{@log_file} not found for Nightly Security Audit.")
    end
  end

  defp analyze_line(line, acc) do
    # Simulate "Decompiler Standard" analysis
    # For instance, we might look for specific keywords like "malformed", "unauthorized", "bypass"
    # in the decompiled claw-speak human-in-the-loop traffic.

    acc_updated = Map.update!(acc, :total_processed, &(&1 + 1))

    line_lower = String.downcase(line)

    cond do
      String.contains?(line_lower, "critical") || String.contains?(line_lower, "unauthorized") ->
        Map.update!(acc_updated, :critical_warnings, &(&1 + 1))
      String.contains?(line_lower, "malformed") || String.contains?(line_lower, "anomaly") ->
        Map.update!(acc_updated, :anomalies, &(&1 + 1))
      true ->
        acc_updated
    end
  end
end
