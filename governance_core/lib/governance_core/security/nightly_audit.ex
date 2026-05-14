defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Runs a nightly security audit analyzing human-in-the-loop agent traffic.
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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      start_pos =
        if stat.size < last_pos do
          0 # File was truncated/rotated
        else
          last_pos
        end

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, start_pos)

          # Process lazily
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

          new_pos =
            case :file.position(file, :cur) do
              {:ok, pos} -> pos
              _ -> start_pos
            end

          File.close(file)

          log_results(critical_logs)

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log file: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Audit log file #{log_path} not found.")
      state
    end
  end

  defp log_results(logs) do
    snippet =
      if Enum.empty?(logs) do
        "No critical findings."
      else
        Enum.join(logs, "")
      end

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    Logger.info("""
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    ---------------------------------
    """)
  end
end
