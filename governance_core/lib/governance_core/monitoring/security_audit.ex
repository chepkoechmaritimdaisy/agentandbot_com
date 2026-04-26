defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit that summarizes human-in-the-loop traffic logs
  conforming to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  @log_file "priv/agent_traffic.log"

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
    new_pos = perform_audit(state.last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(last_pos) do
    Logger.info("SecurityAudit: Running nightly security audit...")

    log_path = Path.join(File.cwd!(), @log_file)

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log truncation/rotation
      pos_to_use = if stat.size < last_pos, do: 0, else: last_pos

      {:ok, file_pid} = :file.open(String.to_charlist(log_path), [:read, :binary])
      :file.position(file_pid, pos_to_use)

      # Stream the log line by line to prevent OOM
      stream = IO.binstream(file_pid, :line)

      findings = Enum.reduce(stream, [], fn line, acc ->
        if String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED") do
          [String.trim(line) | acc]
        else
          acc
        end
      end)

      {:ok, final_pos} = :file.position(file_pid, :cur)
      :file.close(file_pid)

      if length(findings) > 0 do
        generate_report(Enum.reverse(findings))
      else
        Logger.info("SecurityAudit: No critical findings in traffic.")
      end

      final_pos
    else
      Logger.warning("SecurityAudit: Log file #{log_path} not found.")
      last_pos
    end
  end

  defp generate_report(findings) do
    report_file = Path.join(File.cwd!(), "priv/security_audit_report.txt")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    snippet = Enum.join(findings, "\n")

    report_content = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    File.write!(report_file, report_content)
    Logger.info("SecurityAudit: Generated decompiler standard report at #{report_file}")
  end
end
