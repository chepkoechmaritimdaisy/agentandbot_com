defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Automated Security Audit for Human-in-the-loop (HitL) traffic.
  Adheres to the "Decompiler Standard" for analyzing agent communication.
  Runs nightly and summarizes critical warnings.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.ClawSpeak

  # Run nightly (24h). For demo, we can manually trigger it.
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    Logger.info("Security Audit System started.")
    # Subscribe to traffic
    Phoenix.PubSub.subscribe(GovernanceCore.PubSub, "clawspeak:traffic")
    # Schedule nightly run
    schedule_audit()
    {:ok, []} # State is a list of traffic events for the day
  end

  def handle_info({:traffic, raw_binary}, state) do
    # Accumulate traffic for analysis
    event = %{
      timestamp: DateTime.utc_now(),
      raw: raw_binary,
      decoded: ClawSpeak.decode(raw_binary)
    }
    # Keep last 1000 events to avoid memory explosion in this demo
    new_state = [event | state] |> Enum.take(1000)
    {:noreply, new_state}
  end

  def handle_info(:run_nightly_audit, state) do
    perform_audit(state)
    schedule_audit()
    # Reset state after audit (or archive it)
    {:noreply, []}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_nightly_audit, @interval)
  end

  def perform_audit(events) do
    Logger.info("Starting Nightly Security Audit on #{length(events)} events...")

    critical_warnings =
      events
      |> Enum.map(&analyze_event/1)
      |> Enum.reject(&(&1 == :ok))

    if Enum.empty?(critical_warnings) do
      Logger.info("Security Audit Passed: No critical issues found.")
    else
      Logger.warning("Security Audit Found Issues:")
      Enum.each(critical_warnings, fn warning ->
        Logger.warning(" - #{warning}")
      end)
    end
  end

  defp analyze_event(%{decoded: {:error, reason}, timestamp: ts}) do
    "Corrupt Frame at #{ts}: #{inspect(reason)}"
  end

  defp analyze_event(%{decoded: {:ok, frame, _}, raw: raw}) do
    payload_size = byte_size(frame.arg)

    cond do
      payload_size > 1024 ->
        "Large Payload Detected: #{payload_size} bytes from Agent #{frame.from}"

      frame.op == 0xFF -> # Hypothetical dangerous opcode
        "Critical: Restricted Opcode 0xFF used by Agent #{frame.from}"

      true ->
        :ok
    end
  end

  # Helper to manually trigger audit for testing
  def trigger_audit do
    GenServer.send(__MODULE__, :run_nightly_audit)
  end
end
