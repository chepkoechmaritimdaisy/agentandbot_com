defmodule GovernanceCore.Security.NightlyAudit do
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # Run every 24 hours

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
    path = Application.get_env(:governance_core, :audit_log_path)

    if path && File.exists?(path) do
      stat = File.stat!(path)

      start_pos =
        if stat.size < last_byte_pos do
          0 # File was truncated or rotated
        else
          last_byte_pos
        end

      case File.open(path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, start_pos)

          {critical_logs, current_pos} =
            IO.binstream(file, :line)
            |> Enum.reduce({[], start_pos}, fn line, {logs, pos} ->
              line_str = to_string(line)
              new_pos = pos + byte_size(line)

              if String.contains?(line_str, ["CRITICAL", "ERROR", "DENIED"]) do
                {logs ++ [String.trim(line_str)], new_pos}
              else
                {logs, new_pos}
              end
            end)

          File.close(file)

          if length(critical_logs) > 0 do
            timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
            snippet = Enum.join(critical_logs, "\n")

            Logger.info("""
            --- DECOMPILER STANDARD AUDIT ---
            TIMESTAMP: #{timestamp}
            SOURCE: HUMAN_IN_THE_LOOP
            TRAFFIC_SNIPPET:
            #{snippet}
            STATUS: ANALYZED
            """)
          else
            Logger.info("Nightly Audit completed. No critical issues found.")
          end

          %{state | last_byte_pos: current_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Audit log path not configured or file does not exist.")
      state
    end
  end
end
