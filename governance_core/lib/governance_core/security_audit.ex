defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly audit for "Human-in-the-loop" agent traffic based on the Decompiler Standard.
  Analyzes and summarizes traffic to only present critical warnings.
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

  def handle_info(:audit_traffic, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit_traffic, @interval)
  end

  def perform_audit do
    Logger.info("Starting Nightly Security Audit (Human-in-the-loop)...")

    # In a real system, this would fetch from a traffic logging database.
    traffic_logs = fetch_daily_traffic()

    critical_warnings = analyze_traffic(traffic_logs)

    if Enum.empty?(critical_warnings) do
      Logger.info("Security Audit: No critical warnings found today.")
    else
      Logger.error("Security Audit: Found #{length(critical_warnings)} critical warnings!")
      Enum.each(critical_warnings, fn warning ->
        Logger.error("  - #{warning.reason}: #{inspect(warning.payload)}")
      end)
    end
  end

  defp fetch_daily_traffic do
    # Simulated daily traffic
    [
      %{id: "t-1", op: 1, payload: "routine check", requires_human: false},
      %{id: "t-2", op: 5, payload: "access granted", requires_human: true},
      %{id: "t-3", op: 99, payload: "unauthorized root access attempt", requires_human: true} # Suspicious
    ]
  end

  defp analyze_traffic(logs) do
    logs
    |> Enum.filter(&(&1.requires_human))
    |> Enum.filter(fn log ->
      # Simulated 'Decompiler Standard' analysis logic
      is_suspicious?(log.payload)
    end)
    |> Enum.map(fn log ->
      %{reason: "Suspicious payload content", payload: log.payload}
    end)
  end

  defp is_suspicious?(payload) do
    String.contains?(payload, "unauthorized") || String.contains?(payload, "root")
  end
end
