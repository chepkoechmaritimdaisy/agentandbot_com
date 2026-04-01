defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Runs nightly audits of "Human-in-the-loop" agent traffic logs according
  to the Decompiler Standard. It summarizes the findings to provide early
  warnings about suspicious traffic or vulnerabilities.
  """
  use GenServer
  require Logger

  # Nightly run (24 hours)
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit_logs, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit_logs, @interval)
  end

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit on #{@log_file} from byte position #{last_pos}...")

    case File.stat(@log_file) do
      {:ok, stat} ->
        # If the file size is smaller than our last read position, it was likely rotated
        start_pos = if stat.size < last_pos, do: 0, else: last_pos

        {new_pos, summary} = analyze_file(@log_file, start_pos)

        report_summary(summary)

        Logger.info("Finished Nightly Security Audit. New byte position: #{new_pos}")
        %{state | last_byte_pos: new_pos}

      {:error, :enoent} ->
        Logger.info("Log file #{@log_file} does not exist yet. Skipping audit.")
        state

      {:error, reason} ->
        Logger.error("Failed to stat log file: #{inspect(reason)}")
        state
    end
  end

  defp analyze_file(filepath, start_pos) do
    case File.open(filepath, [:read]) do
      {:ok, file} ->
        # Move to our starting position
        :file.position(file, start_pos)

        # Process the rest of the file using IO.binstream
        stream = IO.binstream(file, :line)

        summary = Enum.reduce(stream, %{suspicious: 0, errors: 0, total: 0}, fn line, acc ->
          process_line(line, acc)
        end)

        # Get the new position
        {:ok, new_pos} = :file.position(file, :cur)
        File.close(file)

        {new_pos, summary}

      {:error, reason} ->
        Logger.error("Failed to open log file for reading: #{inspect(reason)}")
        {start_pos, %{suspicious: 0, errors: 0, total: 0}}
    end
  end

  defp process_line(line, acc) do
    acc = %{acc | total: acc.total + 1}

    cond do
      String.contains?(line, "ERROR") ->
        %{acc | errors: acc.errors + 1}
      String.contains?(line, "suspicious") or String.contains?(line, "unauthorized") ->
        %{acc | suspicious: acc.suspicious + 1}
      true ->
        acc
    end
  end

  defp report_summary(summary) do
    Logger.info("""
    --- SECURITY AUDIT SUMMARY ---
    Total Lines Evaluated: #{summary.total}
    Suspicious Activity: #{summary.suspicious}
    Errors Encountered: #{summary.errors}
    ------------------------------
    """)

    if summary.suspicious > 0 do
       Logger.warning("Decompiler Standard Alert: Detected #{summary.suspicious} suspicious activities in agent traffic!")
    end
  end
end
