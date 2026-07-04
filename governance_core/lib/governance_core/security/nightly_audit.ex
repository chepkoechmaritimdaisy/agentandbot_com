defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze "Human-in-the-loop" agent traffic,
  formatting and summarizing critical findings according to the 'Decompiler Standard'.
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

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      process_log(log_path)
    else
      Logger.warning("Audit log path not configured or file does not exist: #{inspect(log_path)}")
    end
  end

  defp process_log(log_path) do
    content = File.read!(log_path)
    lines = String.split(content, "\n")

    # Filter for critical keywords
    critical_lines = Enum.filter(lines, fn line ->
      upcased = String.upcase(line)
      String.contains?(upcased, "CRITICAL") or
        String.contains?(upcased, "ERROR") or
        String.contains?(upcased, "DENIED")
    end)

    if Enum.empty?(critical_lines) do
      Logger.info("Nightly Audit: No critical traffic findings.")
    else
      snippet = Enum.join(critical_lines, "\n")

      # Format according to the 'Decompiler Standard'
      report = """
      === DECOMPILER STANDARD SECURITY AUDIT ===
      Date: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      Status: CRITICAL FINDINGS DETECTED
      ---
      TRAFFIC_SNIPPET:
      #{snippet}
      ==========================================
      """

      Logger.error("Nightly Security Audit Report:\n#{report}")
    end
  end
end
