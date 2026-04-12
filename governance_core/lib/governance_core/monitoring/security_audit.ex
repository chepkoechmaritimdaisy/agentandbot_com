defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Reads 'Human-in-the-loop' agent traffic from `log/agent_traffic.log`.
  Tracks `last_byte_pos` to avoid reprocessing.
  Formats analysis output according to 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  @log_file "log/agent_traffic.log"
  # 24 hours
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

  defp run_audit(state) do
    last_pos = state.last_byte_pos

    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      start_pos =
        if stat.size < last_pos do
          # Log rotated or truncated
          0
        else
          last_pos
        end

      case File.open(@log_file, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, start_pos)

          # Process lines lazily with binstream and reduce to prevent OOM
          stats =
            IO.binstream(file, :line)
            |> Enum.reduce(%{lines_read: 0, approvals: 0, rejections: 0}, fn line, acc ->
                 # Simplified parsing logic for the example
                 line_str = to_string(line)
                 acc = %{acc | lines_read: acc.lines_read + 1}

                 cond do
                   String.contains?(line_str, "APPROVAL") -> %{acc | approvals: acc.approvals + 1}
                   String.contains?(line_str, "REJECTION") -> %{acc | rejections: acc.rejections + 1}
                   true -> acc
                 end
               end)

          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          log_summary(stats)

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("SecurityAudit failed to open log file: #{inspect(reason)}")
          %{state | last_byte_pos: start_pos}
      end
    else
      Logger.info("SecurityAudit: Log file #{@log_file} does not exist.")
      state
    end
  end

  defp log_summary(stats) do
    if stats.lines_read > 0 do
      summary = """
      --- DECOMPILER STANDARD SECURITY SUMMARY ---
      Total Human-in-the-loop actions: #{stats.lines_read}
      Approved: #{stats.approvals}
      Rejected: #{stats.rejections}
      Status: COMPLETE
      --------------------------------------------
      """
      Logger.info("\n" <> summary)
    end
  end
end
