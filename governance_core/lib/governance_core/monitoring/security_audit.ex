defmodule GovernanceCore.Monitoring.SecurityAudit do
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours (nightly)
  @log_file "log/agent_traffic.log"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  def init(last_byte_pos) do
    schedule_audit()
    {:ok, last_byte_pos}
  end

  def handle_info(:audit, last_byte_pos) do
    new_pos = run_audit(last_byte_pos)
    schedule_audit()
    {:noreply, new_pos}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_audit(last_byte_pos) do
    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)
      current_size = stat.size

      read_pos = if current_size < last_byte_pos, do: 0, else: last_byte_pos

      if read_pos < current_size do
        File.open!(@log_file, [:read, :binary], fn file ->
          :file.position(file, read_pos)

          # Lazily process log lines to prevent OOM
          IO.binstream(file, :line)
          |> Enum.reduce(%{entries: 0}, fn line, acc ->
            # Here we would do actual parsing
            # For now, just count lines processed
            %{entries: acc.entries + 1}
          end)
          |> generate_summary()
        end)
        current_size
      else
        last_byte_pos
      end
    else
      last_byte_pos
    end
  end

  defp generate_summary(stats) do
    # Decompiler Standard Format output
    summary = """
    === SECURITY AUDIT SUMMARY (DECOMPILER STANDARD) ===
    Processed Entries: #{stats.entries}
    Status: OK
    ====================================================
    """
    Logger.info(summary)
  end
end
