defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for Human-in-the-loop agent traffic.
  Follows Decompiler Standard.
  """
  use GenServer
  require Logger

  @file_path "log/agent_traffic.log"
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

  defp perform_audit(%{last_byte_pos: pos} = state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard) from byte position #{pos}...")

    case File.stat(@file_path) do
      {:ok, %{size: size}} when size > pos ->
        # There's new content to read
        new_pos = read_and_audit(pos)
        %{state | last_byte_pos: new_pos}

      {:ok, %{size: size}} when size < pos ->
        # Log rotated, start from 0
        Logger.info("Log file was rotated, restarting audit from position 0.")
        new_pos = read_and_audit(0)
        %{state | last_byte_pos: new_pos}

      {:ok, _} ->
        # No new content
        Logger.info("No new agent traffic to audit.")
        state

      {:error, reason} ->
        Logger.error("Failed to stat #{@file_path}: #{inspect(reason)}")
        state
    end
  end

  defp read_and_audit(start_pos) do
    case :file.open(String.to_charlist(@file_path), [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, start_pos)

        # Read stream
        # Stream.resource doesn't easily support byte positions with file modes natively if you just use File.stream! with offset
        # A simpler way is to just use IO.binstream
        stream = IO.binstream(file, :line)

        Enum.each(stream, fn line ->
          process_line(line)
        end)

        {:ok, new_pos} = :file.position(file, :cur)
        :file.close(file)

        Logger.info("Security Audit completed. New byte position: #{new_pos}")
        new_pos

      {:error, reason} ->
        Logger.error("Failed to open #{@file_path}: #{inspect(reason)}")
        start_pos
    end
  end

  defp process_line(line) do
    # Basic check complying with "Decompiler Standard"
    # Example: Look for human-in-the-loop approvals or sensitive data
    if String.contains?(line, "human-in-the-loop") or String.contains?(line, "approval") do
      Logger.warning("Security Audit (Decompiler Standard): Critical Human-in-the-loop interaction found: #{String.trim(line)}")
    end
  end
end
