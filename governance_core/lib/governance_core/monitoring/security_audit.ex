defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for "Human-in-the-loop" agent traffic,
  parsing log/agent_traffic.log and analyzing warnings per the
  "Decompiler Standard".
  """
  use GenServer
  require Logger

  # Run every 24 hours
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    # On boot, we just record the current file size so we don't audit past logs
    state =
      if File.exists?(@log_file) do
        %{size: size} = File.stat!(@log_file)
        %{state | last_byte_pos: size}
      else
        state
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

  defp perform_audit(state) do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard)...")

    if File.exists?(@log_file) do
      %{size: current_size} = File.stat!(@log_file)

      # Handle file rotation (size shrank)
      start_pos =
        if current_size < state.last_byte_pos do
          0
        else
          state.last_byte_pos
        end

      bytes_to_read = current_size - start_pos

      if bytes_to_read > 0 do
        file = File.open!(@log_file, [:read])
        :file.position(file, start_pos)

        # Read the newly added content
        new_content = IO.binread(file, bytes_to_read)
        File.close(file)

        lines =
          if new_content == :eof, do: [], else: String.split(new_content, "\n", trim: true)

        critical_warnings =
          lines
          |> Enum.filter(fn line ->
            String.contains?(line, "[WARNING]") or String.contains?(line, "[CRITICAL]")
          end)

        if Enum.empty?(critical_warnings) do
          Logger.info("Security Audit: No critical warnings found in agent traffic today.")
        else
          Logger.warning("Security Audit Summary: Found #{length(critical_warnings)} critical warnings.")
          Enum.each(critical_warnings, &Logger.warning("Traffic Audit: #{String.trim(&1)}"))
        end

        %{state | last_byte_pos: current_size}
      else
        Logger.info("Security Audit: No new logs to audit.")
        state
      end
    else
      Logger.debug("Security Audit: #{@log_file} not found, skipping.")
      state
    end
  end
end
