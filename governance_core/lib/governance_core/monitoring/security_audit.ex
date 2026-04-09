defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Processes human-in-the-loop agent traffic directly from the `log/agent_traffic.log` file.
  Uses file streams and tracks the last byte position to prevent reprocessing old logs,
  applying the "Decompiler Standard" logic.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Security Audit (Nightly)...")
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:run_audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  def perform_audit(state) do
    Logger.info("Running Nightly Security Audit...")

    if File.exists?(@log_file) do
      process_log_file(state)
    else
      Logger.warning("Log file #{@log_file} not found. Skipping audit.")
      state
    end
  end

  defp process_log_file(state) do
    case File.open(@log_file, [:read]) do
      {:ok, file} ->
        # Seek to the last known position
        case :file.position(file, state.last_pos) do
          {:ok, _} -> :ok
          _ -> :file.position(file, 0) # fallback to start if seek fails
        end

        # Process remaining lines using a stream
        stream = IO.binstream(file, :line)

        {warnings, final_pos} = Enum.reduce(stream, {0, state.last_pos}, fn line, {warn_count, pos} ->
          new_pos = pos + byte_size(line)

          # Only process lines related to human-in-the-loop traffic
          if String.contains?(line, "Human approved message") or String.contains?(line, "human_handoff") do
            if violates_decompiler_standard?(line) do
              Logger.warning("[Security Audit] Traffic violates Decompiler Standard: #{String.trim(line)}")
              {warn_count + 1, new_pos}
            else
              {warn_count, new_pos}
            end
          else
            {warn_count, new_pos}
          end
        end)

        File.close(file)

        # In a real system, you might summarize the warnings and send a digest
        if warnings > 0 do
          Logger.warning("Nightly Security Audit completed with #{warnings} critical warning(s) for human review.")
        else
          Logger.info("Nightly Security Audit completed successfully. No Decompiler Standard violations.")
        end

        %{state | last_pos: final_pos}

      {:error, reason} ->
        Logger.error("Failed to open log file #{@log_file}: #{inspect(reason)}")
        state
    end
  end

  defp violates_decompiler_standard?(line) do
    # "Decompiler Standard" logic (mocked)
    # E.g. ensuring frames are 8 bytes, CRC32 verified, and not obfuscated.
    # We might flag anything with suspicious hex or missing standard metadata.
    # For now, flag lines containing "invalid_crc" or "obfuscated"
    String.contains?(line, "invalid_crc") or String.contains?(line, "obfuscated")
  end
end
