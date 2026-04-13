defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that runs a nightly audit of agent traffic from `log/agent_traffic.log`.
  Formats its analysis according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # Nightly interval (24 hours)
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = run_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Path.join(File.cwd!(), "log/agent_traffic.log")

    if File.exists?(log_path) do
      # Handle file truncation/rotation
      file_size = File.stat!(log_path).size
      read_pos = if file_size < last_byte_pos, do: 0, else: last_byte_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          # Use IO.binstream and Enum.reduce to lazily process without loading entire file in memory
          stream = IO.binstream(file, :line)

          # We perform the reduction to count occurrences, this is just an example analysis
          analysis = Enum.reduce(stream, %{total_lines: 0, suspicious_events: 0}, fn line, acc ->
            is_suspicious = String.contains?(line, "UNAUTHORIZED") or String.contains?(line, "SUSPICIOUS")

            %{
              total_lines: acc.total_lines + 1,
              suspicious_events: if(is_suspicious, do: acc.suspicious_events + 1, else: acc.suspicious_events)
            }
          end)

          # Get new byte position
          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          # Output according to the Decompiler Standard
          Logger.info("""
          [DECOMPILER STANDARD AUDIT]
          TARGET: log/agent_traffic.log
          ANALYSIS_RESULT:
          - Total New Events Analyzed: #{analysis.total_lines}
          - Suspicious Events Flagged: #{analysis.suspicious_events}
          STATUS: COMPLETED
          """)

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("SecurityAudit: Failed to open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.info("SecurityAudit: Log file not found, skipping analysis.")
      state
    end
  end
end
