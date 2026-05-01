defmodule GovernanceCore.Monitoring.NightlyAudit do
  @moduledoc """
  A GenServer that processes human-in-the-loop agent traffic nightly.
  Formats critical findings according to the Decompiler Standard.
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
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      read_pos = if stat.size < state.last_byte_pos, do: 0, else: state.last_byte_pos

      if stat.size > read_pos do
        case File.open(log_path, [:read, :binary]) do
          {:ok, io} ->
            :file.position(io, read_pos)

            findings =
              IO.binstream(io, :line)
              |> Enum.reduce([], fn line, acc ->
                if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
                  [line | acc]
                else
                  acc
                end
              end)
              |> Enum.reverse()

            File.close(io)

            if !Enum.empty?(findings) do
              report = format_report(findings)
              Logger.info("Nightly Audit Report:\n#{report}")
            end

            %{state | last_byte_pos: stat.size}

          {:error, reason} ->
            Logger.error("NightlyAudit failed to open log file: #{inspect(reason)}")
            state
        end
      else
        state
      end
    else
      Logger.info("NightlyAudit: Log file not found at path: #{inspect(log_path)}")
      state
    end
  end

  defp format_report(findings) do
    snippet = Enum.join(findings, "")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_string()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
