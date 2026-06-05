defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze "Human-in-the-loop" agent traffic
  and generate an audit report adhering to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
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

  defp perform_audit do
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    case File.read(log_path) do
      {:ok, contents} ->
        critical_logs = filter_critical_logs(contents)
        report = format_report(critical_logs)
        Logger.info("Nightly Security Audit Complete:\n#{report}")

      {:error, reason} ->
        Logger.error("Failed to read audit log path #{log_path}: #{inspect(reason)}")
    end
  end

  defp filter_critical_logs(contents) do
    contents
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
