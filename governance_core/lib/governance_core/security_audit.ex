defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly security audit for Human-in-the-loop agent traffic.
  Processes log/agent_traffic.log and summarizes critical warnings
  according to the 'Decompiler Standard'.
  """

  use GenServer
  require Logger

  # Nightly interval (24 hours)
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_state) do
    schedule_audit()
    {:ok, %{}}
  end

  def handle_info(:audit, state) do
    Logger.info("Starting Nightly Security Audit for Agent Traffic...")
    process_traffic()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp process_traffic do
    if File.exists?(@log_file) do
      # Stream to prevent loading entirely in memory
      critical_events =
        File.stream!(@log_file)
        |> Enum.reduce([], fn line, acc ->
          if is_critical?(line) do
            [line | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      summarize(critical_events)
    else
      Logger.info("Security Audit: No traffic log found at #{@log_file}")
    end
  end

  defp is_critical?(line) do
    # Simple heuristic representing "Decompiler Standard" for human-in-the-loop critical warnings
    String.contains?(line, "[CRITICAL]") or String.contains?(line, "UNAUTHORIZED_ACCESS") or String.contains?(line, "HUMAN_OVERRIDE_FAILED")
  end

  defp summarize([]) do
    Logger.info("Security Audit Complete: No critical human-in-the-loop warnings found.")
  end

  defp summarize(events) do
    Logger.warning("Security Audit Complete: #{length(events)} critical warnings identified!")

    Enum.each(Enum.take(events, 5), fn evt ->
      Logger.warning("  - " <> String.trim(evt))
    end)

    if length(events) > 5 do
      Logger.warning("  ... and #{length(events) - 5} more.")
    end
  end
end
