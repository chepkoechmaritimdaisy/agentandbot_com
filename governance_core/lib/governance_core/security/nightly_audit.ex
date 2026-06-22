defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Performs nightly security audits on human-in-the-loop agent traffic.
  Summarizes and formats findings using the Decompiler Standard, keeping only critical alerts for the morning review.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{}}
  end

  @impl true
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

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      critical_snippets = process_logs(log_path)

      if length(critical_snippets) > 0 do
        report = generate_report(critical_snippets)
        Logger.warning("Nightly Audit completed with findings:\n#{report}")
      else
        Logger.info("Nightly Audit completed: No critical findings.")
      end
    else
      Logger.info("Nightly Audit skipped: Log file not found at #{inspect(log_path)}")
    end
  end

  defp process_logs(path) do
    File.stream!(path)
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
    end)
  end

  defp generate_report(snippets) do
    snippet_text = Enum.join(snippets, "")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet_text}
    STATUS: ANALYZED
    """
  end
end
