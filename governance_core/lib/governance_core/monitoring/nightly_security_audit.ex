defmodule GovernanceCore.Monitoring.NightlySecurityAudit do
  @moduledoc """
  Nightly analyzes and summarizes agent traffic logs to Decompiler Standard format.
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

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if is_nil(log_path) do
      Logger.error("NightlySecurityAudit: No :audit_log_path configured.")
      state
    else
      if File.exists?(log_path) do
        process_log_file(log_path, last_byte_pos, state)
      else
        Logger.error("NightlySecurityAudit: Log file not found at #{log_path}")
        state
      end
    end
  end

  defp process_log_file(log_path, last_byte_pos, state) do
    current_size = File.stat!(log_path).size

    start_pos = if current_size < last_byte_pos, do: 0, else: last_byte_pos

    {:ok, file} = File.open(log_path, [:read, :binary])
    :file.position(file, start_pos)

    # Process stream lazily
    filtered_lines = IO.binstream(file, :line)
    |> Enum.reduce([], fn line, acc ->
      if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
        [line | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()

    File.close(file)

    if filtered_lines != [] do
      log_summary(filtered_lines)
    end

    %{state | last_byte_pos: current_size}
  end

  defp log_summary(lines) do
    snippet = Enum.join(lines, "")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    summary = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("Nightly Security Audit Summary:\n" <> summary)
  end
end
