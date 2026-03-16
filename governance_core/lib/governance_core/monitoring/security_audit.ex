defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that runs nightly to audit human-in-the-loop agent traffic
  from `log/agent_traffic.log` according to the Decompiler Standard.
  Keeps track of the last read byte position.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
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

  def perform_audit(state) do
    Logger.info("Starting Nightly Security Audit...")

    case File.stat(@log_file) do
      {:ok, %{size: size}} ->
        if size > state.last_pos do
          process_new_logs(state.last_pos)
          Logger.info("Security Audit completed.")
          %{state | last_pos: size}
        else
          Logger.info("No new logs to audit.")
          state
        end

      {:error, :enoent} ->
        Logger.info("Log file #{@log_file} not found.")
        state

      {:error, reason} ->
        Logger.error("Failed to stat #{@log_file}: #{inspect(reason)}")
        state
    end
  end

  defp process_new_logs(last_pos) do
    case :file.open(String.to_charlist(@log_file), [:read, :binary]) do
      {:ok, io_device} ->
        :file.position(io_device, {:bof, last_pos})
        read_lines(io_device)
        :file.close(io_device)
      {:error, reason} ->
        Logger.error("Could not open log file: #{inspect(reason)}")
    end
  end

  defp read_lines(io_device) do
    case :file.read_line(io_device) do
      {:ok, line} ->
        analyze_log_line(line)
        read_lines(io_device)
      :eof -> :ok
      {:error, reason} ->
        Logger.error("Error reading line: #{inspect(reason)}")
    end
  end

  defp analyze_log_line(line) do
    # Perform Decompiler Standard analysis here.
    if String.contains?(line, "CRITICAL") do
      Logger.warning("Security Audit found critical traffic issue: #{String.trim(line)}")
    end
  end
end
