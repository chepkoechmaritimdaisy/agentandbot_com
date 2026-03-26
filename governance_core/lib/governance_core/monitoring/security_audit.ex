defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  GenServer that runs nightly auditing of Human-in-the-loop agent traffic
  log entries from log/agent_traffic.log using file streams to prevent
  reprocessing old logs, adhering to the "Decompiler Standard".
  """
  use GenServer
  require Logger

  # Nightly audit interval: 24 hours
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_pos = perform_audit(state.last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(last_byte_pos) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      file_stat = File.stat!(@log_file)
      current_size = file_stat.size

      # Handle file truncation/rotation
      pos_to_read = if current_size < last_byte_pos, do: 0, else: last_byte_pos

      if current_size > pos_to_read do
        # Open file in read mode and jump to the last_byte_pos to only read new lines
        {:ok, file} = :file.open(String.to_charlist(@log_file), [:read, :binary])
        :file.position(file, pos_to_read)

        # Process the rest of the stream
        IO.binstream(file, :line)
        |> Enum.each(&analyze_log_entry/1)

        :file.close(file)
        Logger.info("Nightly Security Audit completed. New log pos: #{current_size}")
        current_size
      else
        Logger.info("Nightly Security Audit completed. No new logs. Pos: #{pos_to_read}")
        pos_to_read
      end
    else
      Logger.info("Audit Log #{@log_file} does not exist. Skipping.")
      0
    end
  end

  defp analyze_log_entry(line) do
    # Placeholder for the Decompiler Standard analysis logic.
    # We log critical warnings if any "human-in-the-loop" constraints are breached.
    if String.contains?(line, "HUMAN_OVERRIDE_FAILED") do
      Logger.warning("Decompiler Standard Alert: Found human override failure -> #{String.trim(line)}")
    end

    if String.contains?(line, "CRITICAL_ACTION_WITHOUT_APPROVAL") do
      Logger.error("Decompiler Standard Alert: Critical action executed without human approval -> #{String.trim(line)}")
    end
  end
end
