defmodule GovernanceCore.Monitoring.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze Human-in-the-loop agent traffic.
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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      current_pos = if stat.size < last_pos, do: 0, else: last_pos

      {snippets, final_pos} = process_log_file(log_path, current_pos)

      generate_report(snippets)

      %{state | last_byte_pos: final_pos}
    else
      Logger.warning("Audit log path not configured or file does not exist.")
      state
    end
  end

  defp process_log_file(path, start_pos) do
    {:ok, file} = File.open(path, [:read, :binary])
    :file.position(file, start_pos)

    {snippets, bytes_read} =
      IO.binstream(file, :line)
      |> Enum.reduce({[], 0}, fn line, {acc, read_bytes} ->
        line_str = to_string(line)
        new_acc =
          if String.contains?(line_str, ["CRITICAL", "ERROR", "DENIED"]) do
            [String.trim(line_str) | acc]
          else
            acc
          end
        {new_acc, read_bytes + byte_size(line)}
      end)

    File.close(file)
    {Enum.reverse(snippets), start_pos + bytes_read}
  end

  defp generate_report([]) do
    Logger.info("Nightly Audit complete. No critical findings.")
  end

  defp generate_report(snippets) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet_text = Enum.join(snippets, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet_text}
    STATUS: ANALYZED
    """

    # Normally this might be saved to a database or sent to a dashboard.
    # For now, we log the standardized report.
    Logger.info("Nightly Audit Report Generated:\n#{report}")
  end
end
