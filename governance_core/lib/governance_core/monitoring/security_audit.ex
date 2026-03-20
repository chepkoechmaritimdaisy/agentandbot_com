defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Automates security and audit logs according to the Decompiler Standard.
  Processes human-in-the-loop agent traffic directly from the log file,
  tracking byte positions to prevent reprocessing.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # Run nightly
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

  def perform_audit(state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      try do
        file = File.open!(@log_file, [:read])

        # Seek to the last processed position to avoid reprocessing old logs
        :file.position(file, {:bof, state.last_pos})

        # Process the log file line by line
        logs_stream = IO.stream(file, :line)

        {hitl_count, new_pos} = Enum.reduce(logs_stream, {0, state.last_pos}, fn line, {count, pos} ->
          # Process the traffic according to the 'Decompiler Standard'
          if String.contains?(line, "human-in-the-loop") or String.contains?(line, "human_handoff") do
            Logger.info("Audited human-in-the-loop traffic: #{String.trim(line)}")
            {count + 1, pos + byte_size(line)}
          else
            {count, pos + byte_size(line)}
          end
        end)

        File.close(file)

        Logger.info("Nightly Security Audit Complete. Found #{hitl_count} critical 'human-in-the-loop' events. Summarized for morning review.")
        %{state | last_pos: new_pos}
      rescue
        e ->
          Logger.error("Failed to process agent traffic log: #{inspect(e)}")
          state
      end
    else
      Logger.warning("Log file #{@log_file} not found. Skipping Nightly Security Audit.")
      state
    end
  end
end
