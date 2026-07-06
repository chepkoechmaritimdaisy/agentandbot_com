defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to audit agent traffic requiring "Human-in-the-loop" approval.
  Formats findings according to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours in ms
  @interval 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{}}
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
      content = File.read!(log_path)

      lines = String.split(content, "\n", trim: true)

      # Filter for critical, error, or denied
      critical_lines = Enum.filter(lines, fn line ->
        line_upcase = String.upcase(line)
        String.contains?(line_upcase, "CRITICAL") or
        String.contains?(line_upcase, "ERROR") or
        String.contains?(line_upcase, "DENIED")
      end)

      snippet = Enum.join(critical_lines, "\n")

      summary = """
      === DECOMPILER STANDARD SECURITY AUDIT ===
      Date: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      Total critical events: #{length(critical_lines)}

      [TRAFFIC_SNIPPET START]
      #{snippet}
      [TRAFFIC_SNIPPET END]
      """

      # Usually this would be written somewhere or emailed, but for the instruction
      # we log it out nicely so Jules only sees critical warnings.
      Logger.warning(summary)
    else
      Logger.info("No audit log found at configured path to analyze.")
    end
  end
end
