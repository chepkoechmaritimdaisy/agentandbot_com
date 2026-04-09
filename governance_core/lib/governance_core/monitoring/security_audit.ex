defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Periodically reads the human-in-the-loop agent traffic log file
  and processes it according to the "Decompiler Standard" to detect security issues.
  Reads lazily to prevent OOM errors and tracks byte position for log rotation.
  """
  use GenServer
  require Logger

  @audit_interval 86_400_000 # Run daily (simulated for nightly audits)
  # For dev/testing we can run it every 5 minutes:
  # @audit_interval 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first audit soon
    Process.send_after(self(), :audit, 5000)
    {:ok, %{last_byte_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = do_audit(state)
    Process.send_after(self(), :audit, @audit_interval)
    {:noreply, new_state}
  end

  defp do_audit(%{last_byte_pos: last_pos} = state) do
    # Nightly Security Audits process human-in-the-loop agent traffic directly from the
    # `log/agent_traffic.log` file using file streams as per memory
    log_dir = "log"
    File.mkdir_p!(log_dir)
    log_path = Path.join(log_dir, "agent_traffic.log")

    # Create file if it doesn't exist
    unless File.exists?(log_path) do
      File.touch!(log_path)
    end

    case File.stat(log_path) do
      {:ok, %File.Stat{size: current_size}} ->
        # Handle file rotation or truncation
        read_pos = if current_size < last_pos, do: 0, else: last_pos

        if current_size > read_pos do
          Logger.info("SecurityAudit: Processing traffic log from byte #{read_pos}")

          # Open file, read from last position lazily
          new_pos =
            File.open!(log_path, [:read, :binary], fn file ->
              :file.position(file, read_pos)

              # Process lines lazily via Enum.reduce/3 to prevent OOM
              # Accumulate summary info according to the Decompiler Standard
              final_acc =
                IO.binstream(file, :line)
                |> Enum.reduce(%{lines_processed: 0, threats_detected: 0}, fn line, acc ->
                  process_line(line, acc)
                end)

              summarize(final_acc)

              {:ok, final_pos} = :file.position(file, :cur)
              final_pos
            end)

          %{state | last_byte_pos: new_pos}
        else
          # No new data
          state
        end

      {:error, reason} ->
        Logger.warning("SecurityAudit: Failed to stat log file: #{inspect(reason)}")
        state
    end
  end

  defp process_line(line, acc) do
    # Process the line to detect "threats" based on the Decompiler Standard.
    # We will simulate the Decompiler Standard analysis here.
    acc = Map.update!(acc, :lines_processed, &(&1 + 1))

    if String.contains?(line, "MALICIOUS") or String.contains?(line, "UNAUTHORIZED") do
      Map.update!(acc, :threats_detected, &(&1 + 1))
    else
      acc
    end
  end

  defp summarize(acc) do
    if acc.lines_processed > 0 do
      Logger.info("""
      SecurityAudit Nightly Summary (Decompiler Standard):
      Processed Lines: #{acc.lines_processed}
      Threats Detected: #{acc.threats_detected}
      """)
    end
  end
end
