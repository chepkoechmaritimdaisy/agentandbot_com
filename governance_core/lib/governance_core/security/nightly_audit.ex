defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit according to the Decompiler Standard.
  Analyzes human-in-the-loop agent traffic and logs critical findings.
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
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      content = File.read!(log_path)

      critical_lines =
        content
        |> String.split("\n")
        |> Enum.filter(fn line ->
          String.contains?(line, "CRITICAL") or
            String.contains?(line, "ERROR") or
            String.contains?(line, "DENIED")
        end)
        |> Enum.join("\n")

      if critical_lines != "" do
        Logger.warning("""
        === DECOMPILER STANDARD NIGHTLY AUDIT ===
        TRAFFIC_SNIPPET:
        #{critical_lines}
        =========================================
        """)
      else
        Logger.info("Nightly Audit completed: No critical findings in agent traffic.")
      end
    else
      Logger.info("Nightly Audit skipped: Audit log path not configured or file missing.")
    end
  end
end
