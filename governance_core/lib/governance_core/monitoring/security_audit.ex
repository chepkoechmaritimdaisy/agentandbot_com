defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit process processing human-in-the-loop agent traffic
  from `log/agent_traffic.log` directly via file streams.
  Tracks file byte position to prevent reprocessing old logs.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
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

  defp perform_audit(state) do
    Logger.info("Starting SecurityAudit...")
    last_pos = state.last_pos

    if File.exists?(@log_file) do
      try do
        {:ok, io_device} = :file.open(@log_file, [:read, :binary])
        :file.position(io_device, {:bof, last_pos})

        # Read from stream and process line by line
        new_pos = read_and_process(io_device, last_pos)
        :file.close(io_device)

        Logger.info("SecurityAudit completed. Processed up to byte position: #{new_pos}")
        %{state | last_pos: new_pos}
      rescue
        e ->
          Logger.error("SecurityAudit encountered an error: #{inspect(e)}")
          state
      end
    else
      Logger.info("SecurityAudit: No agent_traffic.log found. Skipping.")
      state
    end
  end

  defp read_and_process(io_device, pos) do
    case IO.binread(io_device, :line) do
      :eof ->
        pos
      {:error, reason} ->
        Logger.error("SecurityAudit error reading file: #{inspect(reason)}")
        pos
      line when is_binary(line) ->
        # We perform "Decompiler Standard" analysis on the traffic line
        analyze_traffic(line)
        # return the updated pos
        {:ok, new_pos} = :file.position(io_device, :cur)
        read_and_process(io_device, new_pos)
    end
  end

  defp analyze_traffic(line) do
    # Perform Decompiler Standard verification, searching for flags/anomalies
    if String.contains?(line, "suspicious") do
      Logger.warning("SecurityAudit Warning (Decompiler Standard): Detected anomalous traffic: #{line}")
    end
  end
end
