defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly process to analyze `log/agent_traffic.log` using file streams.
  Tracks `last_byte_pos` to prevent reprocessing old logs, and resets to 0 if the
  file size is smaller than `last_byte_pos`.
  Analyzes traffic for the "Decompiler Standard".
  """
  use GenServer
  require Logger

  # Nightly interval (e.g., 24 hours), but for testing purposes we can make it shorter or just schedule it
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
    # Memory: "Nightly Security Audits process human-in-the-loop agent traffic directly from the log/agent_traffic.log file using file streams, tracking the last byte position to prevent reprocessing old logs."
    # Memory: "When implementing log file tracking in Elixir to prevent reprocessing (e.g., Nightly Security Audits), handle file truncation or log rotation by comparing File.stat!(file).size against last_byte_pos. If the file size is smaller, reset the read position to 0; otherwise, use :file.position and IO.binstream."
    # Memory: "Security audits for 'Human-in-the-loop' agent traffic must follow the 'Decompiler Standard' and run nightly."

    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      current_pos =
        if stat.size < last_byte_pos do
          Logger.info("SecurityAudit: Log file rotated or truncated. Resetting read position to 0.")
          0
        else
          last_byte_pos
        end

      if stat.size > current_pos do
        process_log_file(current_pos)
      else
        Logger.debug("SecurityAudit: No new logs to process.")
        current_pos
      end
    else
      Logger.debug("SecurityAudit: Log file #{@log_file} does not exist.")
      last_byte_pos
    end
  end

  defp process_log_file(start_pos) do
    Logger.info("SecurityAudit: Processing log file from byte #{start_pos} for Decompiler Standard...")

    case File.open(@log_file, [:read, :binary]) do
      {:ok, io_device} ->
        :file.position(io_device, start_pos)

        # We read lines using IO.binstream to process it efficiently
        stream = IO.binstream(io_device, :line)

        Enum.each(stream, fn line ->
          analyze_line(line)
        end)

        # Get the new position
        {:ok, new_pos} = :file.position(io_device, :cur)
        File.close(io_device)

        Logger.info("SecurityAudit: Finished processing log file. New position: #{new_pos}")
        new_pos

      {:error, reason} ->
        Logger.error("SecurityAudit: Failed to open log file: #{inspect(reason)}")
        start_pos
    end
  end

  defp analyze_line(line) do
    # Placeholder for "Decompiler Standard" analysis
    # E.g., looking for critical warnings or specific traffic patterns
    if String.contains?(line, "CRITICAL") do
      Logger.warning("SecurityAudit: Critical Human-in-the-loop warning found in traffic log: #{line}")
    end
  end
end
