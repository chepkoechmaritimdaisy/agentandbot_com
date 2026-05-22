defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  NightlyAudit GenServer.
  Analyzes human-in-the-loop agent traffic nightly according to the Decompiler Standard.
  Filters for critical findings (CRITICAL, ERROR, DENIED) and logs the summary.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, last_pos) do
    new_pos = perform_audit(last_pos)
    schedule_audit()
    {:noreply, new_pos}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(last_pos) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle file truncation or log rotation
      actual_pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, actual_pos)

          findings =
            IO.binstream(file, :line)
            |> Enum.reduce([], fn line, acc ->
              if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
                [line | acc]
              else
                acc
              end
            end)
            |> Enum.reverse()
            |> Enum.join("")

          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          if findings != "" do
            timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

            summary = """
            --- DECOMPILER STANDARD AUDIT ---
            TIMESTAMP: #{timestamp}
            SOURCE: HUMAN_IN_THE_LOOP
            STATUS: ANALYZED
            TRAFFIC_SNIPPET:
            #{findings}
            """

            Logger.info("Nightly Audit Summary:\n#{summary}")
          else
            Logger.info("Nightly Audit completed. No critical findings.")
          end

          new_pos

        {:error, reason} ->
          Logger.error("Failed to open audit log: #{inspect(reason)}")
          actual_pos
      end
    else
      Logger.warning("Audit log path not configured or file does not exist.")
      last_pos
    end
  end
end
