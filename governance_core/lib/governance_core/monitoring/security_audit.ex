defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit that formats and summarizes 'Human-in-the-loop'
  agent traffic according to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

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

  defp perform_audit(state) do
    log_file = Path.join(File.cwd!(), "priv/human_traffic.log")

    if File.exists?(log_file) do
      stat = File.stat!(log_file)

      start_pos =
        if stat.size < state.last_byte_pos do
          # Log rotation detected
          0
        else
          state.last_byte_pos
        end

      File.open(log_file, [:read], fn file ->
        :file.position(file, start_pos)

        # Read lazily to avoid OOM
        {bytes_read, critical_summaries} =
          IO.binstream(file, :line)
          |> Enum.reduce({0, []}, fn line, {acc_bytes, acc_crit} ->
            snippet = String.trim(line)

            crit =
              if is_critical?(snippet) do
                [snippet | acc_crit]
              else
                acc_crit
              end

            {acc_bytes + byte_size(line), crit}
          end)

        if not Enum.empty?(critical_summaries) do
          log_summaries(Enum.reverse(critical_summaries))
        end

        %{state | last_byte_pos: start_pos + bytes_read}
      end) |> case do
        {:ok, new_state} -> new_state
        _ -> state
      end
    else
      Logger.warning("SecurityAudit log file #{log_file} does not exist.")
      state
    end
  end

  defp is_critical?(snippet) do
    upper = String.upcase(snippet)
    String.contains?(upper, "CRITICAL") or String.contains?(upper, "ERROR") or String.contains?(upper, "DENIED")
  end

  defp log_summaries(critical_lines) do
    summary_text = Enum.join(critical_lines, "\n")

    Logger.warning("""
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{summary_text}
    STATUS: ANALYZED (CRITICAL ISSUES FOUND)
    """)
  end
end
