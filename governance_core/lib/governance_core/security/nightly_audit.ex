defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs a nightly audit of agent traffic logs, formatting them
  according to the 'Decompiler Standard'. Only includes logs with CRITICAL, ERROR, or DENIED.
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

  def handle_info(:nightly_audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :nightly_audit, @interval)
  end

  defp perform_audit do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      logs = File.read!(log_path)

      critical_logs = String.split(logs, "\n", trim: true)
      |> Enum.filter(fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)
      |> Enum.join("\n")

      if critical_logs != "" do
        report = """
        --- DECOMPILER STANDARD AUDIT ---
        TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
        SOURCE: HUMAN_IN_THE_LOOP
        TRAFFIC_SNIPPET:
        #{critical_logs}
        STATUS: ANALYZED
        """
        Logger.info("NightlyAudit Report:\n#{report}")
      else
        Logger.info("NightlyAudit: No critical agent traffic found.")
      end
    else
      Logger.debug("NightlyAudit: Audit log file not found at path #{inspect(log_path)}")
    end
  end
end
