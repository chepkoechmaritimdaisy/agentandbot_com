defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  GenServer that runs a nightly audit of agent traffic, filtering for critical
  events and summarizing them according to the Decompiler Standard.
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
  def handle_info(:nightly_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :nightly_audit, @interval)
  end

  defp perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)
      snippet = filter_critical_logs(content)

      report = """
      [DECOMPILER_STANDARD_REPORT]
      NIGHTLY AUDIT SUMMARY:
      TRAFFIC_SNIPPET:
      #{snippet}
      """

      Logger.info("Nightly Audit Complete. Report:\\n#{report}")
    else
      Logger.debug("Nightly Audit skipped: No audit log path configured or file does not exist.")
    end
  end

  defp filter_critical_logs(content) do
    content
    |> String.split("\\n", trim: true)
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
    end)
    |> Enum.join("\\n")
  end
end
