defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Periodically analyzes "Human-in-the-loop" agent traffic, filters for critical findings,
  and formats them according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

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
    Logger.info("NightlyAudit: Starting security audit of agent traffic...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_findings =
        lines
        |> Enum.filter(fn line ->
          String.contains?(line, "CRITICAL") or
          String.contains?(line, "ERROR") or
          String.contains?(line, "DENIED")
        end)

      unless Enum.empty?(critical_findings) do
        formatted_snippet = """
        --- TRAFFIC_SNIPPET ---
        #{Enum.join(critical_findings, "\n")}
        -----------------------
        """
        Logger.info("NightlyAudit: Critical findings detected (Decompiler Standard):\n#{formatted_snippet}")
      else
        Logger.info("NightlyAudit: No critical findings in traffic.")
      end
    else
      Logger.warning("NightlyAudit: Audit log path not configured or file missing.")
    end
  end
end
