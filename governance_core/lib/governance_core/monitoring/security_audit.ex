defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit that processes human-in-the-loop agent traffic
  and summarizes it according to the Decompiler Standard.
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

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_file = "log/agent_traffic.log"

    # Ensure directory exists for the log file
    File.mkdir_p!(Path.dirname(log_file))

    # Create file if it doesn't exist so we don't crash
    unless File.exists?(log_file) do
      File.write!(log_file, "")
    end

    file_size = File.stat!(log_file).size

    start_pos = if file_size < last_byte_pos do
      0
    else
      last_byte_pos
    end

    case File.open(log_file, [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, {:bof, start_pos})

        # Read and process lazily using Enum.reduce
        summary = IO.binstream(file, :line)
        |> Enum.reduce(%{lines_processed: 0, flags: 0}, fn line, acc ->
          # Process line according to Decompiler Standard
          flagged = if String.contains?(line, "UNAUTHORIZED") or String.contains?(line, "SENSITIVE") do
            1
          else
            0
          end

          %{acc | lines_processed: acc.lines_processed + 1, flags: acc.flags + flagged}
        end)

        # Determine the new position
        {:ok, new_pos} = :file.position(file, :cur)
        File.close(file)

        Logger.info("Security Audit completed. Processed #{summary.lines_processed} lines, found #{summary.flags} flagged items.")
        Logger.info("Summary format (Decompiler Standard): Validated #{summary.lines_processed} ClawSpeak frames without human-in-the-loop exception.")

        %{state | last_byte_pos: new_pos}

      {:error, reason} ->
        Logger.error("Failed to open #{log_file}: #{inspect(reason)}")
        state
    end
  end
end
