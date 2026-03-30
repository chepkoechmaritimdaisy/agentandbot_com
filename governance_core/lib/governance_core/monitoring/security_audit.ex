defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Reads human-in-the-loop agent traffic directly from `log/agent_traffic.log`.
  Tracks the last byte position to prevent reprocessing, and handles log rotation.
  """
  use GenServer
  require Logger

  # Run daily
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    Logger.info("GovernanceCore.Monitoring.SecurityAudit started.")
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      # Handle log rotation / truncation
      read_pos =
        if stat.size < last_pos do
          Logger.info("Log file truncated or rotated. Resetting read position to 0.")
          0
        else
          last_pos
        end

      case File.open(@log_file, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          # Process new traffic using IO.binstream
          file
          |> IO.binstream(:line)
          |> Enum.each(&process_log_line/1)

          # Get new position and close
          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          Logger.info("Security Audit completed. New last_byte_pos: #{new_pos}")
          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Agent traffic log file not found at #{@log_file}. Skipping audit.")
      state
    end
  end

  defp process_log_line(line) do
    # Placeholder for actual "Decompiler Standard" analysis logic
    # Here we would normally analyze the line for suspicious human-in-the-loop traffic
    # e.g. Regex match on certain tokens
    if String.contains?(line, "CRITICAL") do
      Logger.warning("Security Audit found critical traffic pattern: #{String.trim(line)}")
    end
  end
end
