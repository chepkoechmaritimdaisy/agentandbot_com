defmodule GovernanceCore.Monitoring.NightlySecurityAudit do
  @moduledoc """
  Nightly analyzes \"Human-in-the-loop\" agent traffic.
  Reads logs dynamically, parses them lazily, tracks read positions,
  and formats critical warnings via the \"Decompiler Standard\".
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      process_log_file(log_path, state.last_byte_pos)
    else
      Logger.debug("Audit log file #{log_path} not found. Skipping audit.")
      state
    end
  end

  defp process_log_file(path, last_byte_pos) do
    stat = File.stat!(path)

    start_pos =
      if stat.size < last_byte_pos do
        # Log rotation or truncation detected
        0
      else
        last_byte_pos
      end

    File.open!(path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      critical_logs =
        IO.binstream(file, :line)
        |> Enum.reduce([], fn line, acc ->
          if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
            [line | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      if not Enum.empty?(critical_logs) do
        report = format_decompiler_standard(critical_logs)
        Logger.warning("Nightly Security Audit Report:\n#{report}")
      end
    end)

    %{last_byte_pos: stat.size}
  end

  defp format_decompiler_standard(logs) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(logs, "")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
