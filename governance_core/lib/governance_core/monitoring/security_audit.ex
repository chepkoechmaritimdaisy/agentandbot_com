defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit processes human-in-the-loop agent traffic directly from
  log/agent_traffic.log using file streams, tracking the last byte position to prevent
  reprocessing old logs.
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

    log_path = Path.join(File.cwd!(), "log/agent_traffic.log")

    # If file doesn't exist, just return state
    if not File.exists?(log_path) do
      Logger.info("No agent traffic log found. Skipping.")
      state
    else
      # Check file size to handle truncation or log rotation
      file_size = File.stat!(log_path).size
      read_pos = if file_size < last_byte_pos, do: 0, else: last_byte_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          {new_pos, summary} =
            IO.binstream(file, :line)
            |> Enum.reduce({read_pos, []}, fn line, {current_pos, acc} ->
              # Very simple "analysis" for the sake of example
              # E.g. we might look for "human-in-the-loop" approval requests
              # and format them into the "Decompiler Standard"
              formatted_line = "DECOMPILER_STD::[SEC_AUDIT] - #{String.trim(line)}"
              {current_pos + byte_size(line), [formatted_line | acc]}
            end)

          File.close(file)

          if summary != [] do
             # Log the Decompiler Standard summary
             Logger.info("Security Audit Summary:\n" <> Enum.join(Enum.reverse(summary), "\n"))
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Could not open log file: #{inspect(reason)}")
          state
      end
    end
  end
end
