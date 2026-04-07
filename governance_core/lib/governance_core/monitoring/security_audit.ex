defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that performs a nightly security audit of agent traffic logs.
  It processes `log/agent_traffic.log` incrementally using file streams to prevent OOM errors,
  handling file truncation/rotation. It summarizes human-in-the-loop interactions.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_path "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_pos = perform_audit(state.last_pos)
    schedule_audit()
    {:noreply, %{state | last_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(last_pos) do
    if File.exists?(@log_path) do
      stat = File.stat!(@log_path)

      # Handle log rotation/truncation
      pos = if stat.size < last_pos, do: 0, else: last_pos

      Logger.info("Starting Security Audit from position #{pos}...")

      case File.open(@log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, {:bof, pos})

          # Process lines lazily using reduce to prevent OOM
          summary =
            IO.binstream(file, :line)
            |> Enum.reduce(%{human_approved: 0, rejected: 0, total_processed: 0}, fn line, acc ->
              process_log_line(line, acc)
            end)

          {:ok, current_pos} = :file.position(file, :cur)
          File.close(file)

          log_summary(summary)
          current_pos

        {:error, reason} ->
          Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
          last_pos
      end
    else
      Logger.info("Security Audit: Agent traffic log not found.")
      last_pos
    end
  end

  defp process_log_line(line, acc) do
    acc = Map.update!(acc, :total_processed, &(&1 + 1))

    cond do
      String.contains?(line, "HUMAN_APPROVED") -> Map.update!(acc, :human_approved, &(&1 + 1))
      String.contains?(line, "HUMAN_REJECTED") -> Map.update!(acc, :rejected, &(&1 + 1))
      true -> acc
    end
  end

  defp log_summary(summary) do
    # Format according to "Decompiler Standard"
    report = """
    === Decompiler Standard Security Audit Report ===
    Total Events Processed: #{summary.total_processed}
    Human-in-the-loop Approved: #{summary.human_approved}
    Human-in-the-loop Rejected: #{summary.rejected}
    =================================================
    """
    Logger.info("\n" <> report)
  end
end
