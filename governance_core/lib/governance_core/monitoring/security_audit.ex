defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process for "Human-in-the-loop" agent traffic.
  Reads traffic from `log/agent_traffic.log` tracking the last byte position to avoid reprocessing.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{last_byte: 0}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = run_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit(%{last_byte: last_byte} = state) do
    Logger.info("Starting Nightly Security Audit...")

    if File.exists?(@log_file) do
      try do
        {:ok, stat} = File.stat(@log_file)

        # If file shrank, it was probably rotated
        start_pos = if stat.size < last_byte, do: 0, else: last_byte

        # Stream the file from the start position
        # We can use File.stream! and drop bytes, but for efficient reading
        # we can open the file and seek to the position.

        new_last_byte = process_log_file(@log_file, start_pos)

        Logger.info("Nightly Security Audit completed. Processed up to byte #{new_last_byte}.")
        %{state | last_byte: new_last_byte}
      rescue
        e ->
          Logger.error("Failed to process agent traffic log: #{inspect(e)}")
          state
      end
    else
      Logger.info("Agent traffic log not found, skipping security audit.")
      state
    end
  end

  defp process_log_file(path, start_pos) do
    File.open!(path, [:read, :utf8], fn file ->
      :file.position(file, start_pos)

      # Process lines until EOF
      # Using a loop to keep reading lines
      stream_lines(file)

      # Return new position
      {:ok, current_pos} = :file.position(file, :cur)
      current_pos
    end)
  end

  defp stream_lines(file) do
    case IO.read(file, :line) do
      :eof -> :ok
      line ->
        analyze_line(line)
        stream_lines(file)
    end
  end

  defp analyze_line(line) do
    # Analyze against "Decompiler Standard"
    # Look for known vulnerability patterns, excessive permissions, or anomalies
    # This is a simplistic check for demonstration purposes

    cond do
      String.contains?(line, "UNAUTHORIZED_ACCESS") ->
        Logger.error("Security Audit: Detected UNAUTHORIZED_ACCESS in traffic log.")
      String.contains?(line, "MALFORMED_PAYLOAD") ->
        Logger.warning("Security Audit: Detected MALFORMED_PAYLOAD in traffic log.")
      String.match?(line, ~r/(DROP|DELETE|UPDATE).*TABLE/i) ->
        Logger.error("Security Audit: Possible SQL injection attempt detected in traffic log.")
      true ->
        :ok
    end
  end
end
