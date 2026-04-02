defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audits processing human-in-the-loop agent traffic
  from log/agent_traffic.log following the Decompiler Standard.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Security Audit...")
    # Schedule immediately or nightly
    Process.send_after(self(), :audit, 5000)
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_pos = perform_audit(state.last_byte_pos)
    Process.send_after(self(), :audit, @interval)
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp perform_audit(last_byte_pos) do
    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_byte_pos do
        0
      else
        last_byte_pos
      end

      if stat.size > read_pos do
        case File.open(@log_file, [:read, :binary], fn file ->
          :file.position(file, read_pos)

          # Read streams line by line from the specific position
          stream = IO.binstream(file, :line)

          Enum.each(stream, fn line ->
            process_log_line(line)
          end)

          # Return the new position
          {:ok, new_pos} = :file.position(file, :cur)
          new_pos
        end) do
          {:ok, final_pos} -> final_pos
          {:error, _} -> read_pos
        end
      else
        read_pos # no new data
      end
    else
      Logger.warning("Log file #{@log_file} does not exist.")
      last_byte_pos
    end
  end

  defp process_log_line(line) do
    # Simplified Decompiler Standard analysis
    # Summarizes findings
    if String.contains?(line, "CRITICAL") do
      Logger.error("[SecurityAudit] Critical finding in traffic: #{String.trim(line)}")
    else
      # Just normal traffic, skip logging to avoid noise
      :ok
    end
  end
end
