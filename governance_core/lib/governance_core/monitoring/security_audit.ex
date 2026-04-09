defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for "Human-in-the-loop" agent traffic,
  processing logs using the Decompiler Standard.
  """
  use GenServer
  require Logger

  @log_file "log/agent_traffic.log"
  # Run nightly (every 24h)
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    # Ensure log directory exists
    File.mkdir_p!("log")
    unless File.exists?(@log_file) do
      File.touch!(@log_file)
    end

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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    current_size =
      case File.stat(@log_file) do
        {:ok, stat} -> stat.size
        {:error, _} -> 0
      end

    # Handle file truncation/rotation
    read_pos = if current_size < last_pos, do: 0, else: last_pos

    new_pos =
      if current_size > read_pos do
        process_log_file(read_pos)
      else
        Logger.info("No new agent traffic to audit.")
        read_pos
      end

    %{state | last_byte_pos: new_pos}
  end

  defp process_log_file(start_pos) do
    case File.open(@log_file, [:read]) do
      {:ok, file} ->
        :file.position(file, start_pos)

        # Read the rest of the file
        stream = IO.binstream(file, :line)

        # We only look for "Human-in-the-loop" approval traffic
        critical_warnings =
          stream
          |> Enum.filter(fn line -> String.contains?(line, "Human-in-the-loop") end)
          |> Enum.map(&analyze_traffic/1)
          |> Enum.reject(&is_nil/1)

        if Enum.empty?(critical_warnings) do
          Logger.info("Security Audit complete. No critical warnings found.")
        else
          Logger.warning("Security Audit complete. Critical warnings:\n" <> Enum.join(critical_warnings, "\n"))
        end

        {:ok, stat} = File.stat(@log_file)
        File.close(file)
        stat.size

      {:error, reason} ->
        Logger.error("Failed to open log file for Security Audit: #{inspect(reason)}")
        start_pos
    end
  end

  defp analyze_traffic(line) do
    # Decompiler Standard analysis logic (simplified for implementation)
    # Check for unauthorized or overly permissive actions within Human-in-the-loop context
    cond do
      String.contains?(line, "grant_admin") ->
        "- CRITICAL: Agent requested admin privileges in: #{String.trim(line)}"
      String.contains?(line, "delete_db") ->
        "- CRITICAL: Agent requested database deletion in: #{String.trim(line)}"
      true ->
        nil
    end
  end
end
