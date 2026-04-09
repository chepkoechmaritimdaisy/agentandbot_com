defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audits process human-in-the-loop agent traffic directly
  from the log/agent_traffic.log file.
  """
  use GenServer
  require Logger

  # Run every night (mocked here as every 24 hours)
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
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    case File.stat(@log_file) do
      {:ok, %{size: size}} ->
        # Handle file truncation or log rotation
        actual_pos = if size < last_byte_pos, do: 0, else: last_byte_pos

        if size > actual_pos do
          process_log_file(actual_pos)
        else
          actual_pos
        end
      {:error, reason} ->
        Logger.error("Failed to stat log file #{@log_file}: #{inspect(reason)}")
        last_byte_pos
    end
  end

  defp process_log_file(start_pos) do
    case File.open(@log_file, [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, start_pos)

        # Read the rest of the file
        new_pos = read_and_audit_lines(file, start_pos)
        File.close(file)
        Logger.info("Nightly Security Audit completed. Summarized audited lines.")
        new_pos
      {:error, reason} ->
        Logger.error("Failed to open log file #{@log_file}: #{inspect(reason)}")
        start_pos
    end
  end

  defp read_and_audit_lines(file, current_pos) do
    # Use reduce directly on the stream to prevent OOM
    bytes_read =
      IO.binstream(file, :line)
      |> Enum.reduce(0, fn line, acc_bytes ->
        audit_line(line)
        acc_bytes + byte_size(line)
      end)

    current_pos + bytes_read
  end

  defp audit_line(line) do
    # Simplified audit logging
    # In a real implementation, this would parse UMP frames or specific formats
    # and summarize critical warnings.
    if String.contains?(line, "CRITICAL") do
      Logger.warning("Security Audit Warning: Found critical entry in human-in-the-loop traffic: #{String.trim(line)}")
    end
  end
end
