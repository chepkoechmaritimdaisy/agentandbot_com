defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  A nightly process that parses "human-in-the-loop" log lines from
  `log/agent_traffic.log` ensuring the Decompiler Standard is met.
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

  def handle_info(:audit_logs, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit_logs, @interval)
  end

  def perform_audit do
    log_file = "log/agent_traffic.log"

    if File.exists?(log_file) do
      Logger.info("Starting Nightly Security Audit on #{log_file}...")

      File.stream!(log_file)
      |> Enum.filter(&is_human_in_loop_traffic?/1)
      |> Enum.each(&analyze_and_report_traffic/1)

      Logger.info("Nightly Security Audit completed.")
    else
      Logger.warning("Security Audit failed: #{log_file} does not exist.")
    end
  end

  defp is_human_in_loop_traffic?(line) do
    String.contains?(line, "[HUMAN_APPROVAL_REQUIRED]") or
    String.contains?(line, "[HITL]")
  end

  defp analyze_and_report_traffic(line) do
    # Summarize traffic log to conform to the Decompiler Standard
    # Check if action was appropriately approved by humans
    if String.contains?(line, "STATUS=UNAPPROVED") do
        Logger.error("Security Audit Alert: Unapproved HITL traffic found! Line: #{String.trim(line)}")
    else
        Logger.info("Security Audit: Approved HITL traffic verified. Line: #{String.trim(line)}")
    end
  end
end
