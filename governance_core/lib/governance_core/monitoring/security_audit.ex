defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit that processes human-in-the-loop agent traffic directly from
  log/agent_traffic.log and summarizes the analysis according to the "Decompiler Standard".
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_path "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    if File.exists?(@log_path) do
      stat = File.stat!(@log_path)

      # Handle log rotation or truncation
      pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(@log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, pos)

          # Process IO.binstream lazily to avoid OOM
          summary =
            IO.binstream(file, :line)
            |> Enum.reduce(%{lines: 0, approvals: 0, rejects: 0, critical: false}, fn line, acc ->
              analyze_line(line, acc)
            end)

          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          if summary.lines > 0 do
            generate_report(summary)
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.warning("SecurityAudit: Could not open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.debug("SecurityAudit: Log file not found at #{@log_path}")
      state
    end
  end

  defp analyze_line(line, acc) do
    # Simple mock analysis for demonstration
    acc = %{acc | lines: acc.lines + 1}

    acc = if String.contains?(line, "APPROVE"), do: %{acc | approvals: acc.approvals + 1}, else: acc
    acc = if String.contains?(line, "REJECT"), do: %{acc | rejects: acc.rejects + 1}, else: acc
    acc = if String.contains?(line, "CRITICAL"), do: %{acc | critical: true}, else: acc

    acc
  end

  defp generate_report(summary) do
    report = """
    === Decompiler Standard Security Audit Report ===
    Total Interventions Processed: #{summary.lines}
    Human Approvals: #{summary.approvals}
    Human Rejections: #{summary.rejects}
    Critical Events Detected: #{summary.critical}
    =================================================
    """

    if summary.critical do
      Logger.error("SecurityAudit CRITICAL ALERT:\n#{report}")
    else
      Logger.info("SecurityAudit Summary:\n#{report}")
    end
  end
end
