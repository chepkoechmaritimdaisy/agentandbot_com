defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  A nightly audit that processes 'Human-in-the-loop' agent traffic
  directly from `log/agent_traffic.log` using file streams.
  Applies the "Decompiler Standard" to log critical warnings.
  """
  use GenServer
  require Logger

  # Run every 24 hours
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

  def perform_audit do
    log_file = "log/agent_traffic.log"
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(log_file) do
      try do
        log_file
        |> File.stream!()
        |> Stream.filter(&human_in_the_loop_traffic?/1)
        |> Stream.each(&apply_decompiler_standard/1)
        |> Stream.run()

        Logger.info("Nightly Security Audit complete.")
      rescue
        e -> Logger.error("Failed to read #{log_file}: #{inspect(e)}")
      end
    else
      Logger.info("Log file #{log_file} does not exist. Skipping audit.")
    end
  end

  # Helper to identify human-in-the-loop traffic.
  defp human_in_the_loop_traffic?(line) do
    # Assuming the log line has some marker for hitl, e.g., "type:hitl" or "approval_required:true"
    String.contains?(String.downcase(line), "hitl") ||
    String.contains?(String.downcase(line), "approval_required") ||
    String.contains?(String.downcase(line), "human-in-the-loop")
  end

  # Applies the Decompiler Standard for analyzing agent traffic.
  defp apply_decompiler_standard(line) do
    # Check for potential anomalies or critical issues
    has_unsafe_payload = String.contains?(line, "eval(") || String.contains?(line, "os.execute") || String.contains?(line, "system(")
    has_auth_bypass = String.contains?(line, "bypass") || String.contains?(line, "admin=true")

    if has_unsafe_payload do
      Logger.warning("[SecurityAudit][Decompiler Standard] CRITICAL WARNING: Unsafe payload detected in HITL traffic: #{String.slice(line, 0, 100)}...")
    end

    if has_auth_bypass do
      Logger.warning("[SecurityAudit][Decompiler Standard] CRITICAL WARNING: Potential auth bypass in HITL traffic: #{String.slice(line, 0, 100)}...")
    end
  end
end
