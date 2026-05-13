defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Nightly Security Audit GenServer.
  Runs every 24 hours to analyze Human-in-the-loop agent traffic
  and generate an audit report in the Decompiler Standard format.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{last_byte_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = run_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit(state) do
    Logger.info("[NightlyAudit] Starting nightly security audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      process_log_file(log_path, state)
    else
      Logger.warning("[NightlyAudit] Audit log path not configured or file missing.")
      state
    end
  end

  defp process_log_file(log_path, state) do
    file_size = File.stat!(log_path).size

    read_pos =
      if file_size < state.last_byte_pos do
        Logger.info("[NightlyAudit] Log file truncated/rotated. Resetting position.")
        0
      else
        state.last_byte_pos
      end

    case File.open(log_path, [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, read_pos)

        findings =
          IO.binstream(file, :line)
          |> Enum.reduce([], fn line, acc ->
            if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
              [line | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()

        new_pos =
          case :file.position(file, :cur) do
            {:ok, pos} -> pos
            _ -> file_size
          end

        File.close(file)

        generate_report(findings)

        %{state | last_byte_pos: new_pos}

      {:error, reason} ->
        Logger.error("[NightlyAudit] Could not open log file: #{inspect(reason)}")
        state
    end
  end

  defp generate_report([]) do
    Logger.info("[NightlyAudit] No critical findings in the audit period.")
  end
  defp generate_report(findings) do
    Logger.info("[NightlyAudit] Generating Decompiler Standard Audit Report...")

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("[NightlyAudit] Generated Report:\n#{report}")

    # Optionally write to file
    report_file = Path.join(File.cwd!(), "priv/nightly_audit.md")
    case File.write(report_file, report, [:append]) do
      :ok -> Logger.info("[NightlyAudit] Report saved to #{report_file}")
      {:error, e} -> Logger.error("[NightlyAudit] Failed to save report: #{inspect(e)}")
    end
  end
end