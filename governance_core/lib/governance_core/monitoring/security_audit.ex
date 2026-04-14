defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit for Agent Traffic.
  Analyzes human-in-the-loop agent traffic directly from log/agent_traffic.log
  using file streams to prevent OOM errors. Outputs summaries formatted to
  the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in ms
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"

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
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    case File.stat(@log_file) do
      {:ok, %{size: size}} ->
        read_pos = if size < last_pos, do: 0, else: last_pos

        case File.open(@log_file, [:read, :binary]) do
          {:ok, file} ->
            :file.position(file, read_pos)

            # Process lazily using IO.binstream and Enum.reduce/3 to avoid OOM
            summary =
              IO.binstream(file, :line)
              |> Enum.reduce(%{total_lines: 0, warnings: []}, fn line, acc ->
                acc = Map.update!(acc, :total_lines, &(&1 + 1))
                if String.contains?(line, "WARN") or String.contains?(line, "ERROR") do
                  Map.update!(acc, :warnings, &[String.trim(line) | &1])
                else
                  acc
                end
              end)

            File.close(file)

            log_summary(summary)

            %{state | last_byte_pos: size}

          {:error, reason} ->
            Logger.error("Failed to open agent traffic log: #{inspect(reason)}")
            state
        end

      {:error, :enoent} ->
        Logger.info("Agent traffic log file not found. Skipping audit.")
        state

      {:error, reason} ->
        Logger.error("Failed to stat agent traffic log: #{inspect(reason)}")
        state
    end
  end

  defp log_summary(summary) do
    # Format per "Decompiler Standard"
    Logger.info("""
    === Decompiler Standard Security Summary ===
    Total Lines Processed: #{summary.total_lines}
    Critical Warnings: #{length(summary.warnings)}
    Details: #{inspect(Enum.take(summary.warnings, 5))}
    ============================================
    """)
  end
end
