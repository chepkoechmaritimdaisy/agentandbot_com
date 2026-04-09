defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for Human-in-the-loop agent traffic.
  Follows the 'Decompiler Standard'.
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

  def perform_audit(%{last_byte_pos: last_byte_pos}) do
    Logger.info("Starting Nightly Security Audit for Agent Traffic...")

    log_path = "log/agent_traffic.log"

    case File.stat(log_path) do
      {:ok, stat} ->
        # Handle log truncation/rotation
        start_pos = if stat.size < last_byte_pos, do: 0, else: last_byte_pos

        # Process new log entries
        new_pos = process_log(log_path, start_pos)
        %{last_byte_pos: new_pos}

      {:error, :enoent} ->
        Logger.debug("No agent traffic log found to audit.")
        %{last_byte_pos: 0}

      {:error, reason} ->
        Logger.error("Failed to read agent traffic log: #{inspect(reason)}")
        %{last_byte_pos: last_byte_pos}
    end
  end

  defp process_log(path, start_pos) do
    File.open!(path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      IO.binstream(file, :line)
      |> Enum.each(fn line ->
        analyze_line(line)
      end)

      case :file.position(file, :cur) do
        {:ok, new_pos} -> new_pos
        _ -> start_pos
      end
    end)
  end

  defp analyze_line(line) do
    # Analyze human-in-the-loop traffic for Decompiler Standard compliance
    if String.contains?(line, "human-in-the-loop") do
      if String.contains?(line, "decompiler_standard: false") do
        Logger.error("Security Audit Flag: Traffic failed Decompiler Standard check: #{String.trim(line)}")
      end
    end
  end
end
