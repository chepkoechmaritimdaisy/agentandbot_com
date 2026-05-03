defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Reads agent traffic logs, analyzes 'Human-in-the-loop' traffic, and
  generates a summary report matching the Decompiler Standard.
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
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      process_log_file(log_path, state)
    else
      Logger.debug("Audit log file path not configured or file missing.")
      state
    end
  end

  defp process_log_file(log_path, %{last_byte_pos: last_byte_pos} = state) do
    current_size = File.stat!(log_path).size

    start_pos =
      if current_size < last_byte_pos do
        # File was truncated/rotated
        0
      else
        last_byte_pos
      end

    if start_pos < current_size do
      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, start_pos)

          findings =
            IO.binstream(file, :line)
            |> Enum.reduce([], fn line, acc ->
               if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
                 [String.trim(line) | acc]
               else
                 acc
               end
            end)
            |> Enum.reverse()

          new_pos = current_size
          File.close(file)

          if not Enum.empty?(findings) do
            log_report(findings)
          else
            Logger.info("Nightly Security Audit passed with no critical findings.")
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log: #{inspect(reason)}")
          state
      end
    else
      Logger.info("Nightly Security Audit: No new logs to process.")
      state
    end
  end

  defp log_report(findings) do
    snippet = Enum.join(findings, "\n")
    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    ---------------------------------
    """

    Logger.info("Nightly Security Audit Report:\n#{report}")
  end
end
