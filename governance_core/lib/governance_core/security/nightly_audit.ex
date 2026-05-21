defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit (every 24 hours).
  Analyzes "Human-in-the-loop" agent traffic logs, finds critical incidents,
  and formats the summary using the Decompiler Standard.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, %{last_byte_pos: last_byte_pos} = state) do
    new_pos = perform_audit(last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(last_byte_pos) do
    Logger.info("Starting Nightly Security Audit...")

    path = Application.get_env(:governance_core, :audit_log_path)

    if path && File.exists?(path) do
      stat = File.stat!(path)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_byte_pos, do: 0, else: last_byte_pos

      {critical_logs, new_pos} = scan_file(path, read_pos)

      if length(critical_logs) > 0 do
        report = format_report(critical_logs)
        Logger.info("\n#{report}")
      else
        Logger.info("Nightly Security Audit completed. No critical incidents found.")
      end

      new_pos
    else
      Logger.warning("Audit log path not configured or file does not exist: #{inspect(path)}")
      last_byte_pos
    end
  end

  defp scan_file(path, start_pos) do
    file = File.open!(path, [:read, :binary])
    :file.position(file, start_pos)

    stream = IO.binstream(file, :line)

    {logs, _acc_pos} =
      Enum.reduce(stream, {[], start_pos}, fn line, {acc_logs, current_pos} ->
        new_pos = current_pos + byte_size(line)

        if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
          {[line | acc_logs], new_pos}
        else
          {acc_logs, new_pos}
        end
      end)

    # Getting the final position after all lines have been processed
    {:ok, final_pos} = :file.position(file, :cur)
    File.close(file)

    {Enum.reverse(logs), final_pos}
  end

  defp format_report(logs) do
    snippet = Enum.join(logs, "")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
