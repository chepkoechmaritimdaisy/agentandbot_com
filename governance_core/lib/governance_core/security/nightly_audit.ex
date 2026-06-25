defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Nightly Security Audits for "Human-in-the-loop" agent traffic, formatting summaries
  according to the project's 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

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
    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(:code.priv_dir(:governance_core) || Path.join(File.cwd!(), "priv"), "agent_traffic.log")

    if File.exists?(log_path) do
      Logger.info("NightlyAudit: Analyzing #{log_path}")
      lines = File.read!(log_path) |> String.split("\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      if Enum.empty?(critical_lines) do
        Logger.info("NightlyAudit: No critical issues found.")
      else
        snippet = Enum.join(critical_lines, "\n")

        # Decompiler Standard Format
        report = """
        === NIGHTLY SECURITY AUDIT ===
        Status: ATTENTION REQUIRED
        TRAFFIC_SNIPPET:
        #{snippet}
        ==============================
        """

        Logger.warning("NightlyAudit Report:\n#{report}")
      end
    else
      Logger.info("NightlyAudit: Log file #{log_path} not found. Skipping audit.")
    end
  end
end
