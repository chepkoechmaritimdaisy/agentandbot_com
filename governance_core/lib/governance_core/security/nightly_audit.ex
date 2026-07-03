defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit to process "Human-in-the-loop" agent traffic logs.
  Filters logs for critical warnings (CRITICAL, ERROR, DENIED) and formats them
  using the Decompiler Standard (TRAFFIC_SNIPPET) for summary reviews.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    # Retrieve the dynamic file path from application config to avoid hardcoding
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, ["CRITICAL", "ERROR", "DENIED"])
      end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Audit Complete: No critical human-in-the-loop interventions required.")
      else
        snippet = Enum.join(critical_lines, "\n")
        report = format_decompiler_standard(snippet)
        Logger.error("Nightly Audit Complete with Findings:\n#{report}")

        # Save report for morning review
        report_path = Path.join(File.cwd!(), "priv/nightly_audit_report.md")
        File.write!(report_path, report)
      end
    else
      Logger.info("Nightly Security Audit: Log file #{log_path} not found. Skipping analysis.")
    end
  end

  defp format_decompiler_standard(snippet) do
    """
    ## DECOMPILER STANDARD: NIGHTLY SECURITY AUDIT

    The following traffic required "Human-in-the-loop" attention and crossed critical thresholds:

    ### TRAFFIC_SNIPPET
    ```log
    #{snippet}
    ```

    Please review the agent behaviors above immediately.
    """
  end
end
