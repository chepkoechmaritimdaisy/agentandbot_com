defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs every 24 hours to analyze agent traffic logs for security issues.
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

  defp perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle file truncation/rotation
      current_pos =
        if stat.size < last_byte_pos do
          0
        else
          last_byte_pos
        end

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, current_pos)

          # Lazily read lines to prevent OOM
          {new_pos, findings} =
            IO.binstream(file, :line)
            |> Enum.reduce({current_pos, []}, fn line, {pos, acc} ->
              new_pos = pos + byte_size(line)

              if contains_critical_keywords?(line) do
                {new_pos, [line | acc]}
              else
                {new_pos, acc}
              end
            end)

          File.close(file)

          if length(findings) > 0 do
            report = format_report(Enum.reverse(findings))
            Logger.warning("Nightly Security Audit findings:\n#{report}")
            # In a real app, we might save this report somewhere or email it.
          else
            Logger.info("Nightly Security Audit completed with no new critical findings.")
          end

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

  defp contains_critical_keywords?(line) do
    String.contains?(line, "CRITICAL") or
    String.contains?(line, "ERROR") or
    String.contains?(line, "DENIED")
  end

  defp format_report(findings) do
    snippet = Enum.join(findings, "")
    timestamp = DateTime.utc_now() |> DateTime.to_string()

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
