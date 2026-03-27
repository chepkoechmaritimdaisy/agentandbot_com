defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that performs nightly security audits on agent traffic logs,
  summarizing them according to the Decompiler Standard.
  Tracks last read position to prevent reprocessing.
  """
  use GenServer
  require Logger

  # Run every 24 hours
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    # Ensure log directory exists
    File.mkdir_p!(Path.dirname(@log_file))

    unless File.exists?(@log_file) do
      File.touch!(@log_file)
    end

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

  defp perform_audit(last_byte_pos) do
    Logger.info("Starting Nightly Security Audit on Human-in-the-loop traffic...")

    case File.stat(@log_file) do
      {:ok, stat} ->
        current_pos =
          if stat.size < last_byte_pos do
            # File was truncated/rotated
            0
          else
            last_byte_pos
          end

        # Read new contents
        case File.open(@log_file, [:read, :binary]) do
          {:ok, file} ->
            :file.position(file, current_pos)

            # Process lines
            lines = IO.binstream(file, :line) |> Enum.to_list()

            if length(lines) > 0 do
              summarize_traffic(lines)
            else
              Logger.info("No new traffic to audit.")
            end

            # Get new position
            {:ok, new_pos} = :file.position(file, :cur)
            File.close(file)

            Logger.info("Nightly Security Audit completed.")
            new_pos

          {:error, reason} ->
            Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
            current_pos
        end

      {:error, reason} ->
        Logger.error("Failed to stat agent traffic log: #{inspect(reason)}")
        last_byte_pos
    end
  end

  defp summarize_traffic(lines) do
    # Perform summary based on the "Decompiler Standard"
    Logger.info("=== Security Audit Summary (Decompiler Standard) ===")
    Logger.info("Processed #{length(lines)} log entries requiring human-in-the-loop validation.")

    # Identify critical alerts (e.g., containing "CRITICAL" or "ERROR")
    criticals = Enum.filter(lines, fn line ->
      String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR")
    end)

    if length(criticals) > 0 do
      Logger.warning("Found #{length(criticals)} critical alerts in traffic.")
      Enum.each(Enum.take(criticals, 5), fn line ->
        Logger.warning("  - #{String.trim(line)}")
      end)
    else
      Logger.info("No critical security alerts found in the traffic.")
    end
  end
end
