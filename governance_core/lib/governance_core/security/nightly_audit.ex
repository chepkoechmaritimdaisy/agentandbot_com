defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly audit of "Human-in-the-loop" traffic.
  Summarizes critical findings according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours
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

  defp perform_audit do
    Logger.info("NightlySecurityAudit: Starting audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)

      lines = String.split(content, "\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED")
      end)

      if not Enum.empty?(critical_lines) do
        snippet = Enum.join(Enum.take(critical_lines, 5), "\n")

        report = """
        --- DECOMPILER STANDARD AUDIT ---
        TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
        SOURCE: HUMAN_IN_THE_LOOP
        TRAFFIC_SNIPPET:
        #{snippet}
        STATUS: ANALYZED
        """

        Logger.warning("Nightly Security Audit Findings:\n#{report}")
      else
        Logger.info("NightlySecurityAudit: No critical findings.")
      end
    else
      Logger.info("NightlySecurityAudit: No audit log found at configured path or path not configured.")
    end
  end
end
