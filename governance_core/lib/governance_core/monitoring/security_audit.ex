defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze "Human-in-the-loop" agent traffic logs.
  It ensures compliance with the Decompiler Standard and summarizes critical warnings.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
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
    Logger.info("Nightly Security Audit: Analyzing agent_traffic.log for Decompiler Standard compliance...")

    log_file_path = "log/agent_traffic.log"

    if File.exists?(log_file_path) do
      # Stream the log file
      critical_warnings =
        File.stream!(log_file_path)
        |> Enum.reduce([], fn line, warnings ->
          analyze_line(line, warnings)
        end)

      summarize_warnings(critical_warnings)
    else
      Logger.info("Nightly Security Audit: Log file #{log_file_path} not found. Skipping audit.")
    end
  end

  defp analyze_line(line, warnings) do
    cond do
      # Check for plain text secrets (rudimentary regex match)
      String.match?(line, ~r/(?i)(api_key|password|secret)\s*[:=]\s*["']?[^"'\s]+["']?/) ->
        ["Potential plain text secret found in log" | warnings]

      # Check for manual / bypass actions in HitL logs
      String.match?(line, ~r/(?i)(bypass|override|force)/) ->
        ["HitL Decompiler Standard violation: Bypass/Override action detected" | warnings]

      true ->
        warnings
    end
  end

  defp summarize_warnings(warnings) do
    if Enum.empty?(warnings) do
      Logger.info("Nightly Security Audit: No critical warnings found. Compliant with Decompiler Standard.")
    else
      Logger.warning("Nightly Security Audit found #{length(warnings)} critical warnings:")
      Enum.each(warnings, &Logger.warning/1)
    end
  end
end
