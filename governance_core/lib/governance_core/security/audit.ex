defmodule GovernanceCore.Security.Audit do
  @moduledoc """
  Performs nightly security audit of agent traffic, focusing on "Human-in-the-loop" scenarios.
  Follows the Decompiler Standard for analysis.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.ClawSpeak

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:run_nightly_audit, state) do
    run_nightly_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    # Schedule next run
    Process.send_after(self(), :run_nightly_audit, @interval)
  end

  def run_nightly_audit do
    Logger.info("[SecurityAudit] Starting nightly traffic analysis...")

    # Fetch logs (simulated as there's no DB table for traffic yet)
    traffic_logs = fetch_traffic_logs()

    critical_events =
      traffic_logs
      |> Enum.filter(&is_human_in_the_loop?/1)
      |> Enum.map(&analyze_event/1)
      |> Enum.filter(&is_critical?/1)

    if Enum.any?(critical_events) do
      report_critical_events(critical_events)
    else
      Logger.info("[SecurityAudit] No critical security events found.")
    end
  end

  defp fetch_traffic_logs do
    # Simulation: Generate some traffic entries
    [
      %{id: 1, type: :clawspeak, payload: valid_payload(), timestamp: DateTime.utc_now()},
      %{id: 2, type: :clawspeak, payload: critical_payload(), timestamp: DateTime.utc_now()},
      %{id: 3, type: :clawspeak, payload: valid_payload(), timestamp: DateTime.utc_now()}
    ]
  end

  defp is_human_in_the_loop?(_event), do: true # Assume all are relevant for now

  defp analyze_event(event) do
    # Decompiler Standard Analysis
    case ClawSpeak.decode(event.payload) do
      {:ok, frame, _rest} ->
        %{
          id: event.id,
          status: :decoded,
          frame: frame,
          risk_score: calculate_risk(frame)
        }
      {:error, reason} ->
        %{
          id: event.id,
          status: :error,
          reason: reason,
          risk_score: 100 # High risk for malformed packets
        }
    end
  end

  defp calculate_risk(frame) do
    cond do
      frame.op == 255 -> 100 # Critical opcode (hypothetical)
      byte_size(frame.arg) > 1000 -> 50 # Large payload
      true -> 0
    end
  end

  defp is_critical?(analysis) do
    analysis.risk_score > 80
  end

  defp report_critical_events(events) do
    Logger.error("[SecurityAudit] CRITICAL WARNINGS FOUND:")
    Enum.each(events, fn event ->
      Logger.error(" - Event #{event.id}: Risk Score #{event.risk_score}. Details: #{inspect(event)}")
    end)
  end

  # Helpers for simulation
  defp valid_payload do
    frame = %ClawSpeak{from: 1, to: 2, op: 10, arg: "Hello"}
    {:ok, binary} = ClawSpeak.encode(frame)
    binary
  end

  defp critical_payload do
    frame = %ClawSpeak{from: 1, to: 2, op: 255, arg: "Critical Command"}
    {:ok, binary} = ClawSpeak.encode(frame)
    binary
  end
end
