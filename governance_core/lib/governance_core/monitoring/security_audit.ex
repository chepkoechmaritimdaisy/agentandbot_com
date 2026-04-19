defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A nightly GenServer that analyzes 'Human-in-the-loop' agent traffic
  from `log/agent_traffic.log` and formats findings to the 'Decompiler Standard'.
  """

  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

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

  defp perform_audit(state) do
    Logger.info("Starting Nightly Security Audit...")
    log_path = Path.join(File.cwd!(), "log/agent_traffic.log")

    # Only process if the file exists
    if File.exists?(log_path) do
      process_log(log_path, state)
    else
      Logger.info("Security Audit: No traffic log found at #{log_path}")
      state
    end
  end

  defp process_log(path, state) do
    stat = File.stat!(path)
    current_size = stat.size
    last_pos = state.last_byte_pos

    # Handle file truncation/rotation
    start_pos = if current_size < last_pos, do: 0, else: last_pos

    if current_size > start_pos do
      Logger.info("Processing new agent traffic... (#{current_size - start_pos} bytes)")

      case File.open(path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, {:bof, start_pos})

          # Lazily process to avoid OOM
          summary =
            IO.binstream(file, :line)
            |> Enum.reduce(%{total_lines: 0, flags: []}, fn line, acc ->
              analyze_line(line, acc)
            end)

          File.close(file)
          log_summary(summary)

          %{state | last_byte_pos: current_size}

        {:error, reason} ->
          Logger.error("Security Audit: Failed to open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.debug("Security Audit: No new traffic to analyze.")
      state
    end
  end

  defp analyze_line(line, acc) do
    # Simple analysis looking for sensitive patterns
    flags =
      if String.contains?(line, ["password", "secret", "token", "unauthorized"]) do
        ["Suspicious activity detected: #{String.trim(line)}" | acc.flags]
      else
        acc.flags
      end

    %{acc | total_lines: acc.total_lines + 1, flags: flags}
  end

  defp log_summary(summary) do
    # Formatting to 'Decompiler Standard'
    formatted = """
    === DECOMPILER STANDARD AUDIT REPORT ===
    Total Traffic Entries Analyzed: #{summary.total_lines}
    Critical Warnings: #{length(summary.flags)}

    Details:
    #{Enum.join(Enum.take(summary.flags, 10), "\n")}
    ========================================
    """

    Logger.info(formatted)
  end
end
