defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Every night, analyzes 'Human-in-the-loop' agent traffic according to the
  'Decompiler Standard', summarizing critical findings.
  """
  use GenServer
  require Logger

  # 24 hours
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

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      content = File.read!(log_path)
      lines = String.split(content, "\n", trim: true)

      critical_lines = Enum.filter(lines, fn line ->
        String.contains?(line, "CRITICAL") or
        String.contains?(line, "ERROR") or
        String.contains?(line, "DENIED")
      end)

      if not Enum.empty?(critical_lines) do
        write_summary(critical_lines)
      else
        Logger.info("Nightly Security Audit: No critical findings.")
      end
    else
      Logger.warning("Nightly Security Audit: Log file not found at #{log_path}")
    end
  end

  defp write_summary(critical_lines) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    date_str = Date.to_string(Date.utc_today())
    summary_path = Path.join(priv_dir, "security_audit_#{date_str}.md")

    content = """
    # Nightly Security Audit - #{date_str}

    ## TRAFFIC_SNIPPET (Decompiler Standard)
    #{Enum.join(critical_lines, "\n")}
    """

    File.write!(summary_path, content)
    Logger.info("Nightly Security Audit: Wrote critical findings to #{summary_path}")
  end
end
