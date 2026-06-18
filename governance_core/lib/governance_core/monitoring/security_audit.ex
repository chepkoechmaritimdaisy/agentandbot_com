defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A nightly GenServer task that audits "Human-in-the-loop" traffic.
  Analyzes agent communication against the "Decompiler Standard" and
  summarizes critical warnings.
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

  def handle_info(:perform_security_audit, state) do
    run_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :perform_security_audit, @interval)
  end

  def run_audit do
    Logger.info("Starting nightly Security Audit (Decompiler Standard)...")

    log_path = Application.get_env(:governance_core, :agent_traffic_log_path, "log/agent_traffic.log")

    if File.exists?(log_path) do
      # Stream the log file to avoid loading a massive file into memory
      warnings =
        File.stream!(log_path)
        |> Enum.filter(&String.match?(&1, ~r/critical|injection|malicious|unauthorized/i))

      if Enum.empty?(warnings) do
        Logger.info("Security Audit Passed: No critical traffic warnings found in #{log_path}.")
      else
        Logger.error("Security Audit Found Warnings in #{log_path}! Summarizing for morning review.")
        summarize_warnings(warnings)
      end
    else
      Logger.warning("Security Audit Warning: Log file #{log_path} not found. Skipping analysis.")
    end
  end

  defp summarize_warnings(warnings) do
    # Only show up to 100 warnings to avoid overwhelming logs
    report =
      warnings
      |> Enum.take(100)
      |> Enum.map_join("", fn w -> "- #{String.trim(w)}\n" end)

    Logger.error("Nightly Security Audit Summary:\n\n#{report}")

    if length(warnings) > 100 do
      Logger.error("...and #{length(warnings) - 100} more warnings omitted.")
    end
  end
end
