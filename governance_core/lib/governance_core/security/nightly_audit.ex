defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Summarizes Human-in-the-loop agent traffic nightly according to Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
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
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    case File.read(log_path) do
      {:ok, contents} ->
        critical_lines = extract_critical_traffic(contents)
        report = format_report(critical_lines)
        Logger.info("\n#{report}")
      {:error, :enoent} ->
        Logger.info("No audit log found at #{log_path}, skipping Nightly Audit.")
      {:error, reason} ->
        Logger.error("Failed to read audit log at #{log_path}: #{inspect(reason)}")
    end
  end

  defp extract_critical_traffic(contents) do
    contents
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") ||
      String.contains?(line, "ERROR") ||
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
    #{if snippet == "", do: "No critical findings.", else: snippet}
    STATUS: ANALYZED
    """
  end
end
