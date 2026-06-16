defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that analyzes "Human-in-the-loop" agent traffic every night
  and formats the summary using the Decompiler Standard.
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

    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/agent_traffic.log"

    case File.read(log_path) do
      {:ok, content} ->
        findings = analyze_logs(content)
        report = format_report(findings)
        Logger.info("Nightly Audit Complete:\n#{report}")
      {:error, reason} ->
        Logger.error("Failed to read audit logs at #{log_path}: #{inspect(reason)}")
    end
  end

  defp analyze_logs(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") or
      String.contains?(line, "ERROR") or
      String.contains?(line, "DENIED")
    end)
  end

  defp format_report(findings) do
    snippet = Enum.join(findings, "\n")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{if snippet == "", do: "No critical findings.", else: snippet}
    STATUS: ANALYZED
    """
  end
end
