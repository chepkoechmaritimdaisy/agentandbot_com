defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs nightly security audits by analyzing human-in-the-loop agent traffic
  log files and summarizing them in the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
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

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "/tmp/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      pos = if stat.size < last_pos do
        # Log rotation or truncation happened
        0
      else
        last_pos
      end

      new_pos = process_log(log_path, pos)
      %{state | last_byte_pos: new_pos}
    else
      Logger.warning("Audit log file #{log_path} not found.")
      state
    end
  end

  defp process_log(path, start_pos) do
    File.open!(path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      {critical_findings, final_pos} =
        IO.binstream(file, :line)
        |> Enum.reduce({[], start_pos}, fn line, {findings, _current_pos} ->
          {:ok, new_pos} = :file.position(file, :cur)

          if String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED") do
            {[line | findings], new_pos}
          else
            {findings, new_pos}
          end
        end)

      if length(critical_findings) > 0 do
        findings_text = Enum.reverse(critical_findings) |> Enum.join("")
        report = generate_report(findings_text)
        Logger.info("\n#{report}")
      else
        Logger.info("Nightly Audit complete. No new critical findings.")
      end

      final_pos
    end)
  end

  defp generate_report(snippet) do
    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
