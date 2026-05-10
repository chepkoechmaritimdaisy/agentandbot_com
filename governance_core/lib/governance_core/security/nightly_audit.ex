defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  GenServer that performs a nightly (24hr) security audit of agent traffic logs.
  Filters critical logs and outputs a report in the Decompiler Standard format.
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

  def handle_info(:run_audit, state) do
    new_pos = perform_audit(state.last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  defp perform_audit(last_pos) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      process_log_file(log_path, last_pos)
    else
      Logger.warning("Audit log file not found at: #{log_path}")
      last_pos
    end
  end

  defp process_log_file(file_path, last_pos) do
    stat = File.stat!(file_path)
    current_size = stat.size

    # Handle log rotation or truncation
    actual_pos = if current_size < last_pos, do: 0, else: last_pos

    if current_size > actual_pos do
      File.open!(file_path, [:read, :binary], fn file ->
        :file.position(file, actual_pos)

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

        generate_report(findings)
      end)

      current_size
    else
      Logger.debug("No new log entries to audit.")
      actual_pos
    end
  end

  defp generate_report([]) do
    Logger.info("Nightly Security Audit completed: No critical findings.")
  end

  defp generate_report(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    report_path = Path.join(File.cwd!(), "priv/nightly_audit_report_#{DateTime.to_unix(DateTime.utc_now())}.txt")

    case File.write(report_path, report) do
      :ok ->
        Logger.info("Nightly Security Audit completed. Report saved to #{report_path}")
      {:error, reason} ->
        Logger.error("Failed to write audit report: #{inspect(reason)}")
    end
  end
end
