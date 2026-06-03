defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly audit of agent traffic logs.
  Summarizes and formats findings according to the Decompiler Standard.
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

  defp perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)
      current_size = stat.size

      read_pos = if current_size < last_byte_pos, do: 0, else: last_byte_pos

      if read_pos < current_size do
        process_log(log_path, read_pos)
        %{state | last_byte_pos: current_size}
      else
        state
      end
    else
      Logger.debug("NightlyAudit: Log file not found at #{log_path}")
      state
    end
  end

  defp process_log(path, start_pos) do
    File.open!(path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      findings =
        IO.binstream(file, :line)
        |> Enum.reduce([], fn line, acc ->
          if String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED") do
            [String.trim(line) | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      if length(findings) > 0 do
        report = generate_report(findings)
        Logger.info("\n" <> report)
      end
    end)
  end

  defp generate_report(findings) do
    snippet = Enum.join(findings, "\n")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

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
