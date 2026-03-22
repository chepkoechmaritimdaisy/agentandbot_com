defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Automated GenServer to process human-in-the-loop agent traffic directly from log/agent_traffic.log
  using file streams. Tracks last byte position to avoid reprocessing. Follows Decompiler Standard.
  """

  use GenServer
  require Logger

  # Run every night, simplified here to every 24 hours
  @interval 24 * 60 * 60 * 1000

  @log_file "log/agent_traffic.log"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{last_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_pos = perform_audit(state.last_pos)
    schedule_audit()
    {:noreply, %{state | last_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(last_pos) do
    case File.stat(@log_file) do
      {:ok, %{size: size}} when size > last_pos ->
        # We have new data to read
        read_new_logs(last_pos)

      {:ok, %{size: size}} when size < last_pos ->
        # File was truncated/rotated, start from 0
        read_new_logs(0)

      {:ok, _} ->
        # No new data
        last_pos

      {:error, reason} ->
        Logger.warning("SecurityAudit: Could not access #{@log_file}: #{inspect(reason)}")
        last_pos
    end
  end

  defp read_new_logs(start_pos) do
    # Open file, seek to start_pos, read line by line
    case File.open(@log_file, [:read]) do
      {:ok, io_device} ->
        :file.position(io_device, {:bof, start_pos})

        # Using File.stream! from an opened IO device is tricky,
        # IO.binstream is an option, but we can also just read lines directly
        # or use File.stream! directly with offset if we had one.
        # Let's read lines manually to track position.
        new_pos = read_lines(io_device, start_pos)
        File.close(io_device)
        new_pos

      {:error, reason} ->
        Logger.warning("SecurityAudit: Could not open #{@log_file}: #{inspect(reason)}")
        start_pos
    end
  end

  defp read_lines(io_device, current_pos) do
    case IO.binread(io_device, :line) do
      :eof ->
        current_pos

      {:error, reason} ->
        Logger.error("SecurityAudit: Error reading #{@log_file}: #{inspect(reason)}")
        current_pos

      line when is_binary(line) ->
        analyze_line(line)
        new_pos = current_pos + byte_size(line)
        read_lines(io_device, new_pos)
    end
  end

  defp analyze_line(line) do
    # Perform Decompiler Standard analysis on human-in-the-loop agent traffic
    # This is a stub for the actual analysis logic
    if String.contains?(line, "CRITICAL") do
      Logger.error("SecurityAudit [CRITICAL]: #{String.trim(line)}")
    end
  end
end
