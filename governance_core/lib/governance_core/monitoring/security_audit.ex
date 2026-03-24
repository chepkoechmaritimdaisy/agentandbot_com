defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A nightly GenServer that processes human-in-the-loop agent traffic directly from
  log/agent_traffic.log using file streams, tracking the last byte position to prevent
  reprocessing old logs. Logs critical warnings according to the "Decompiler Standard".
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
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

  defp perform_audit(%{last_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      case File.open(@log_file, [:read, :utf8]) do
        {:ok, file} ->
          {:ok, _} = :file.position(file, last_pos)

          lines =
            IO.stream(file, :line)
            |> Enum.to_list()

          # "Decompiler Standard"
          Enum.each(lines, fn line ->
            if String.contains?(line, "CRITICAL") or String.contains?(line, "UNAUTHORIZED") do
              Logger.warning("Security Audit Warning (Decompiler Standard): #{String.trim(line)}")
            end
          end)

          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)
          Logger.info("Security Audit Complete.")
          %{state | last_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Log file #{@log_file} does not exist. Skipping audit.")
      state
    end
  end
end
