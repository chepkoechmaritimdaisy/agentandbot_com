defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit analyzing Human-in-the-loop traffic logs.
  Formats critical findings according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
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

  def perform_audit do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/default_audit.log"

    case File.read(log_path) do
      {:ok, content} ->
        findings = process_logs(content)
        if findings != "" do
          report = format_report(findings)
          Logger.warning("Nightly Security Audit Report:\n#{report}")
        else
          Logger.info("Nightly Security Audit: No critical findings.")
        end
      {:error, reason} ->
        Logger.error("Nightly Security Audit failed to read log file at #{log_path}: #{inspect(reason)}")
    end
  end

  defp process_logs(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.filter(fn line ->
      String.contains?(line, "CRITICAL") or
      String.contains?(line, "ERROR") or
      String.contains?(line, "DENIED")
    end)
    |> Enum.join("\n")
  end

  defp format_report(findings) do
    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{findings}
    STATUS: ANALYZED
    ---------------------------------
    """
  end
end
