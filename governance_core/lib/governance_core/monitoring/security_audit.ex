defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Reads agent_traffic.log and performs analysis. Uses lazy evaluation
  and position tracking to prevent OOM and redundant reprocessing.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    # Ensure log directory and file exist
    File.mkdir_p!(Path.dirname(@log_file))
    unless File.exists?(@log_file) do
      File.touch!(@log_file)
    end

    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, %{last_pos: last_pos} = state) do
    new_pos = perform_audit(last_pos)
    schedule_audit()
    {:noreply, %{state | last_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(last_pos) do
    Logger.info("Starting Nightly Security Audit...")

    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      # Handle log rotation or truncation
      start_pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(@log_file, [:read, :binary]) do
        {:ok, io_device} ->
          :file.position(io_device, start_pos)

          # Process lazily to avoid OOM
          final_pos =
            IO.binstream(io_device, :line)
            |> Enum.reduce(start_pos, fn line, current_pos ->
              process_log_line(line)
              current_pos + byte_size(line)
            end)

          File.close(io_device)
          Logger.info("Security Audit completed. Final position: #{final_pos}")
          final_pos

        {:error, reason} ->
          Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
          start_pos
      end
    else
      Logger.warning("agent_traffic.log not found, skipping audit.")
      last_pos
    end
  end

  defp process_log_line(line) do
    # Decompiler Standard analysis logic goes here
    # For now, we'll just log critical findings if any patterns match

    # Example logic:
    if String.contains?(line, "CRITICAL") do
      Logger.warning("Security Audit found critical traffic log: #{String.trim(line)}")
    end
    :ok
  end
end
