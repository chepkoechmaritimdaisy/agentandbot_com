defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  GenServer to perform nightly audit on Human-in-the-loop agent traffic based on Decompiler Standard.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

  defp perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/agent_traffic.log"

    if File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Audit completed. No critical findings.")
      else
        snippet = Enum.join(critical_lines, "\n")
        report = """
        [DECOMPILER_STANDARD_REPORT]
        TRAFFIC_SNIPPET:
        #{snippet}
        [/DECOMPILER_STANDARD_REPORT]
        """
        Logger.error("Nightly Audit findings:\n#{report}")
      end
    else
      Logger.warning("Audit log file #{log_path} not found.")
    end
  end
end
