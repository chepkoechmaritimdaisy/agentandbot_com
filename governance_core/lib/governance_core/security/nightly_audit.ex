defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Analyzes "Human-in-the-loop" agent traffic every night according to the
  Decompiler Standard, filtering for critical warnings and summarizing.
  """

  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # Run every 24 hours

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
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      if Enum.empty?(critical_lines) do
        Logger.info("Nightly Security Audit: No critical traffic found.")
      else
        snippet = Enum.join(critical_lines, "\n")

        # Format according to Decompiler Standard
        report = """
        === DECOMPILER STANDARD SECURITY AUDIT ===
        Date: #{Date.utc_today()}
        Status: ATTENTION REQUIRED

        TRAFFIC_SNIPPET:
        #{snippet}
        ==========================================
        """

        Logger.warn("\n" <> report)
      end
    else
      Logger.warn("Nightly Security Audit: Log file not found at path: #{inspect(log_path)}")
    end
  end
end
