defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A nightly GenServer that processes "Human-in-the-loop" agent traffic logs
  adhering to the 'Decompiler Standard'. It maintains the last byte read
  position to avoid reprocessing old logs.
  """

  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # Default interval of 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule_audit(interval)
    {:ok, %{interval: interval, last_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    Logger.info("Starting Nightly Security Audit...")
    new_pos = run_security_audit(state.last_pos)
    schedule_audit(state.interval)
    {:noreply, %{state | last_pos: new_pos}}
  end

  defp schedule_audit(interval) do
    Process.send_after(self(), :audit, interval)
  end

  def run_security_audit(last_pos) do
    # Ensure directory and file exists before opening
    File.mkdir_p!(Path.dirname(@log_file))

    unless File.exists?(@log_file) do
      File.write!(@log_file, "")
    end

    case File.open(@log_file, [:read]) do
      {:ok, file} ->
        # Seek to the last read position
        {:ok, ^last_pos} = :file.position(file, last_pos)

        # Process new lines
        file
        |> IO.binstream(:line)
        |> Enum.each(&process_log_line/1)

        # Save the new position
        {:ok, new_pos} = :file.position(file, :cur)
        File.close(file)

        Logger.info("Nightly Security Audit completed. Summarized traffic up to byte #{new_pos}.")
        new_pos

      {:error, reason} ->
        Logger.error("Nightly Security Audit failed to open log file: #{inspect(reason)}")
        last_pos
    end
  end

  defp process_log_line(line) do
    # Placeholder for 'Decompiler Standard' log processing
    # Here we simulate finding critical issues and summarizing them
    if String.contains?(line, "CRITICAL") do
      Logger.warning("Security Audit flagged critical agent traffic: #{String.trim(line)}")
    end
  end
end
