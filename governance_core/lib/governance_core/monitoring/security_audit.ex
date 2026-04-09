defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Processes human-in-the-loop agent traffic directly from the `log/agent_traffic.log` file using file streams.
  Tracks the last byte position to prevent reprocessing old logs.
  Summarizes logs conforming to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    # Create the log directory if it doesn't exist to prevent crashes on startup
    File.mkdir_p!(Path.dirname(@log_file))

    schedule_audit()
    {:ok, %{last_position: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_position = perform_audit(state.last_position)
    schedule_audit()
    {:noreply, %{state | last_position: new_position}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(last_position) do
    Logger.info("SecurityAudit: Starting nightly Decompiler Standard analysis...")

    case File.open(@log_file, [:read]) do
      {:ok, file} ->
        # Move to the last read position
        :file.position(file, {:bof, last_position})

        # Process lines
        new_position = process_lines(file, last_position)

        File.close(file)
        new_position

      {:error, :enoent} ->
        Logger.info("SecurityAudit: Log file #{@log_file} does not exist yet. Skipping.")
        last_position

      {:error, reason} ->
        Logger.error("SecurityAudit: Failed to open log file #{@log_file}. Reason: #{inspect(reason)}")
        last_position
    end
  end

  defp process_lines(file, current_position) do
    case IO.binread(file, :line) do
      :eof ->
        current_position

      line ->
        process_line(line)
        {:ok, new_pos} = :file.position(file, :cur)
        process_lines(file, new_pos)
    end
  end

  defp process_line(line) do
    # Ensure conformity with 'Decompiler Standard'
    # Currently just logging if it contains human-in-the-loop patterns
    if String.contains?(line, "human-in-the-loop") do
       Logger.warning("SecurityAudit: Critical Human-in-the-loop traffic found: #{String.trim(line)}")
    else
       # Process standard log lines normally
       :ok
    end
  end
end
