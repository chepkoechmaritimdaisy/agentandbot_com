defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs nightly security audits on agent traffic logs.
  It summarizes "Human-in-the-loop" agent traffic using the Decompiler Standard.
  Only flags logs with CRITICAL, ERROR, or DENIED keywords.
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("NightlyAudit: Starting security log analysis...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_byte_pos, do: 0, else: last_byte_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          # Lazily process file line by line to prevent OOM
          stream = IO.binstream(file, :line)

          findings = Enum.reduce(stream, [], fn line, acc ->
            if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
              [String.trim(line) | acc]
            else
              acc
            end
          end) |> Enum.reverse()

          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          if length(findings) > 0 do
            report_findings(findings)
          else
            Logger.info("NightlyAudit: No critical findings in this audit window.")
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("NightlyAudit: Failed to open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("NightlyAudit: Audit log path not configured or file missing.")
      state
    end
  end

  defp report_findings(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.warning("NightlyAudit: Critical findings detected:\n#{report}")

    # In a real app, this might also write to a specific report file or DB
    report_file = Path.join(File.cwd!(), "priv/nightly_audit_report.txt")
    File.write(report_file, report, [:append])
  end
end
