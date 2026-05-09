defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs every 24 hours to analyze traffic logs for 'Human-in-the-loop' agent traffic
  and generates a summary following the Decompiler Standard.
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

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle file truncation/rotation
      actual_pos = if stat.size < last_pos, do: 0, else: last_pos

      {new_pos, findings} = analyze_log(log_path, actual_pos)

      if findings != [] do
        summary = build_summary(findings)
        Logger.info("\n#{summary}")
      else
        Logger.info("Nightly Audit completed. No critical findings.")
      end

      %{state | last_byte_pos: new_pos}
    else
      Logger.debug("Audit log file not configured or does not exist.")
      state
    end
  end

  defp analyze_log(path, pos) do
    File.open!(path, [:read], fn file ->
      :file.position(file, pos)

      stream = IO.binstream(file, :line)

      findings =
        Enum.reduce(stream, [], fn line, acc ->
          if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
            [line | acc]
          else
            acc
          end
        end)

      {:ok, final_pos} = :file.position(file, :cur)
      {final_pos, Enum.reverse(findings)}
    end)
  end

  defp build_summary(findings) do
    snippet =
      findings
      |> Enum.take(10) # Limit snippet size
      |> Enum.join("")
      |> String.trim()

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    ---------------------------------
    """
  end
end
