defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Processes 'Human-in-the-loop' agent traffic logs every night and summarizes them
  according to the 'Decompiler Standard', highlighting critical warnings.
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:run_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  defp perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    # Audit log path should be configured, defaulting to a local file if missing
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      process_log_file(log_path)
    else
      Logger.warning("Audit log file not found at: #{log_path}")
    end
  end

  defp process_log_file(path) do
    content = File.read!(path)

    # Filter lines for critical keywords
    critical_lines =
      content
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line ->
        String.match?(line, ~r/CRITICAL|ERROR|DENIED/i)
      end)

    if Enum.empty?(critical_lines) do
      Logger.info("Nightly Audit Complete: No critical traffic found.")
    else
      snippet = Enum.join(critical_lines, "\n")

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{DateTime.utc_now()}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{snippet}
      STATUS: ANALYZED
      """

      Logger.warning("Nightly Audit Findings:\n#{report}")

      # We could write this report to a file, or keep it in logs
      report_path = Path.join(File.cwd!(), "priv/nightly_audit_report.md")
      File.write!(report_path, report, [:append])
    end
  end
end
