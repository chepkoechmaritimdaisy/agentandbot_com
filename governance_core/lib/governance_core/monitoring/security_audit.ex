defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly Security Audit GenServer that analyzes 'Human-in-the-loop' agent traffic.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours
  @log_file "log/agent_traffic.log"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_audit()
    {:ok, %{last_byte_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_pos = run_audit(state.last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit(last_byte_pos) do
    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      # Handle log rotation or truncation
      pos = if stat.size < last_byte_pos, do: 0, else: last_byte_pos

      if stat.size > pos do
        File.open(@log_file, [:read, :binary], fn file ->
          :file.position(file, pos)

          summary =
            IO.binstream(file, :line)
            |> Enum.reduce(%{lines_read: 0, critical_warnings: 0}, fn line, acc ->
              # Example analysis logic according to "Decompiler Standard"
              # Only keep critical warnings
              acc = %{acc | lines_read: acc.lines_read + 1}
              if String.contains?(line, "CRITICAL") do
                 %{acc | critical_warnings: acc.critical_warnings + 1}
              else
                 acc
              end
            end)

          Logger.info("Nightly Security Audit Summary (Decompiler Standard): Read #{summary.lines_read} lines, Found #{summary.critical_warnings} critical warnings.")
        end)

        stat.size
      else
        pos
      end
    else
      Logger.warning("Security Audit: log file #{@log_file} does not exist.")
      last_byte_pos
    end
  end
end
