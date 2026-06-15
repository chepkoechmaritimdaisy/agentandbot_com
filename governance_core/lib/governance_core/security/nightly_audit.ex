defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs nightly security audits on agent traffic logs.
  Formats critical findings according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000

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
    # Can adjust this to run specifically at night if needed,
    # but a simple 24-hour interval suffices for the basic requirement.
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit do
    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/agent_traffic.log"

    case File.read(log_path) do
      {:ok, content} ->
        findings = process_logs(content)
        if findings != "" do
          report = format_report(findings)
          Logger.warning("Nightly Audit Complete. Findings:\n#{report}")
        else
          Logger.info("Nightly Audit Complete. No critical issues found.")
        end
      {:error, reason} ->
        Logger.error("Failed to read audit log at #{log_path}: #{inspect(reason)}")
    end
  end

  defp process_logs(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") or
      String.contains?(line, "ERROR") or
      String.contains?(line, "DENIED")
    end)
    |> Enum.join("\n")
  end

  defp format_report(snippet) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
