defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audits process "Human-in-the-loop" agent traffic
  directly from log/agent_traffic.log and format summaries according to the "Decompiler Standard".
  """
  use GenServer
  require Logger

  # Nightly interval (e.g., 24 hours). We use a shorter interval for demonstration/testing.
  @interval 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting SecurityAudit")
    # State holds the last byte position
    state = %{last_byte_pos: 0}
    schedule_audit()
    {:ok, state}
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

  defp run_audit(%{last_byte_pos: last_pos} = state) do
    # Assuming the application runs from root or log is relatively placed.
    # Safe fallback using Application dir could be better, but typically it's relative.
    log_file = "log/agent_traffic.log"

    if File.exists?(log_file) do
      stat = File.stat!(log_file)

      current_pos = if stat.size < last_pos do
        # File was truncated or rotated
        0
      else
        last_pos
      end

      if stat.size > current_pos do
        new_pos = process_log(log_file, current_pos)
        %{state | last_byte_pos: new_pos}
      else
        state
      end
    else
      Logger.debug("SecurityAudit: Log file #{log_file} does not exist.")
      state
    end
  end

  defp process_log(log_file, start_pos) do
    File.open!(log_file, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      # Process lazily to prevent OOM
      # Returns {line_count, bytes_read, anomalies_found}
      {lines, _bytes, anomalies} = IO.binstream(file, :line)
      |> Enum.reduce({0, start_pos, []}, fn line, {count, pos, acc} ->
        new_pos = pos + byte_size(line)
        new_acc = if is_anomaly?(line), do: [line | acc], else: acc
        {count + 1, new_pos, new_acc}
      end)

      {:ok, final_pos} = :file.position(file, :cur)

      if lines > 0 do
        generate_report(lines, Enum.reverse(anomalies))
      end

      final_pos
    end)
  end

  defp is_anomaly?(line) do
    # Placeholder anomaly detection logic
    String.contains?(line, "ERROR") || String.contains?(line, "DENIED") || String.contains?(line, "UNAUTHORIZED")
  end

  defp generate_report(total_lines, anomalies) do
    # Format according to the "Decompiler Standard"
    date = Date.utc_today() |> to_string()

    report = """
    === DECOMPILER STANDARD SECURITY AUDIT REPORT ===
    DATE: #{date}
    SCOPE: Human-in-the-loop Agent Traffic
    TOTAL TRAFFIC PROCESSED: #{total_lines} lines
    CRITICAL ALERTS: #{length(anomalies)}

    SUMMARY:
    #{if length(anomalies) == 0, do: "No anomalies detected. Operations normal.", else: "Action required. Review following anomalies:"}

    #{Enum.join(anomalies, "")}
    =================================================
    """

    Logger.info("\n#{report}")

    # Could also write this to a specific audit log file using the priv dir
    priv_dir = :code.priv_dir(:governance_core)
    if is_binary(priv_dir) or is_list(priv_dir) do
      audit_file = Path.join(priv_dir, "audit_#{date}.txt")
      File.write(audit_file, report, [:append])
    end
  end
end
