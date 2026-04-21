defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit that processes human-in-the-loop agent traffic
  from log/agent_traffic.log and formats the output according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    Logger.info("Starting Nightly Security Audit...")

    log_file_path = Path.join(File.cwd!(), "log/agent_traffic.log")

    new_pos =
      if File.exists?(log_file_path) do
        process_log_file(log_file_path, state.last_byte_pos)
      else
        Logger.info("Log file not found, skipping.")
        state.last_byte_pos
      end

    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp process_log_file(path, last_byte_pos) do
    file_size = File.stat!(path).size

    # Handle truncation / log rotation
    pos_to_use =
      if file_size < last_byte_pos do
        0
      else
        last_byte_pos
      end

    File.open!(path, [:read, :binary], fn file ->
      :file.position(file, pos_to_use)

      lines_processed =
        IO.binstream(file, :line)
        |> Enum.reduce(0, fn line, acc ->
          process_line(line)
          acc + 1
        end)

      if lines_processed > 0 do
        Logger.info("Processed #{lines_processed} lines according to Decompiler Standard.")
      end
    end)

    File.stat!(path).size
  end

  defp process_line(line) do
    # Placeholder for actual Decompiler Standard formatting logic
    Logger.info("Decompiler Standard Audit: #{String.trim(line)}")
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end
end
