defmodule GovernanceCore.Security.NightlyAudit do
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

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_file = Application.get_env(:governance_core, :audit_log_path, "priv/audit.log")

    if File.exists?(log_file) do
      stat = File.stat!(log_file)

      # Handle log rotation or truncation
      read_pos =
        if stat.size < last_pos do
          0
        else
          last_pos
        end

      case File.open(log_file, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          {findings, final_pos} =
            IO.binstream(file, :line)
            |> Enum.reduce({[], read_pos}, fn line, {acc, pos} ->
              new_pos = pos + byte_size(line)

              if is_human_in_the_loop_critical?(line) do
                {[line | acc], new_pos}
              else
                {acc, new_pos}
              end
            end)

          File.close(file)

          generate_report(Enum.reverse(findings))

          %{state | last_byte_pos: final_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log file: #{inspect(reason)}")
          state
      end
    else
      Logger.info("Audit log file #{log_file} does not exist. Skipping.")
      state
    end
  end

  defp is_human_in_the_loop_critical?(line) do
    is_hitl = String.contains?(line, "Human-in-the-loop")
    has_critical = String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED")

    is_hitl and has_critical
  end

  defp generate_report([]) do
    Logger.info("Nightly Security Audit completed with no critical findings.")
  end

  defp generate_report(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.warning("Nightly Security Audit Critical Findings:\n#{report}")
  end
end
