defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs every 24 hours to analyze "Human-in-the-loop" agent traffic logs
  and generate an audit report following the Decompiler Standard.
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

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      # Handle file truncation/rotation
      file_size = File.stat!(log_path).size
      read_pos = if file_size < last_pos, do: 0, else: last_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          # Read lazily to avoid OOM
          critical_findings =
            IO.binstream(file, :line)
            |> Enum.reduce([], fn line, acc ->
              if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
                [line | acc]
              else
                acc
              end
            end)
            |> Enum.reverse()

          new_pos = :file.position(file, :cur) |> elem(1)
          File.close(file)

          if length(critical_findings) > 0 do
            generate_report(critical_findings)
          else
             Logger.info("Nightly Audit complete: No critical findings.")
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log file: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Audit log path not configured or file does not exist.")
      state
    end
  end

  defp generate_report(findings) do
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

    Logger.warning("Nightly Security Audit generated critical report:\n#{report}")

    # Write the report to a file for persistent viewing
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    report_path = Path.join(priv_dir, "nightly_audit_report.txt")

    case File.write(report_path, report, [:append]) do
      :ok -> Logger.info("Saved Nightly Audit Report to #{report_path}")
      {:error, reason} -> Logger.error("Failed to save Nightly Audit Report: #{inspect(reason)}")
    end
  end
end
