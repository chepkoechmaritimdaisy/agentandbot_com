defmodule GovernanceCore.Security.NightlyAudit do
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

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
    Logger.info("NightlyAudit starting...")

    new_pos = perform_audit(state.last_byte_pos)

    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(last_byte_pos) do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      pos =
        if stat.size < last_byte_pos do
          0
        else
          last_byte_pos
        end

      if stat.size > pos do
        # We have new data to read
        new_pos = read_and_analyze(log_path, pos)
        new_pos
      else
        pos
      end
    else
      Logger.warning("NightlyAudit: Log path not configured or file does not exist")
      last_byte_pos
    end
  end

  defp read_and_analyze(log_path, start_pos) do
    {:ok, file} = File.open(log_path, [:read, :binary])
    :file.position(file, start_pos)

    # Process lazily
    {snippets, bytes_read} =
      IO.binstream(file, :line)
      |> Enum.reduce({[], 0}, fn line, {acc_snippets, acc_bytes} ->
        if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
          {[line | acc_snippets], acc_bytes + byte_size(line)}
        else
          {acc_snippets, acc_bytes + byte_size(line)}
        end
      end)

    File.close(file)

    if snippets != [] do
      snippet_text =
        Enum.reverse(snippets)
        |> Enum.join("")

      report = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET:
      #{snippet_text}
      STATUS: ANALYZED
      """

      Logger.info("NightlyAudit generated report:\n#{report}")
    end

    start_pos + bytes_read
  end
end
