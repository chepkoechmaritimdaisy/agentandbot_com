defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs nightly security audits (every 24h) on Human-in-the-loop traffic logs.
  Filters for CRITICAL, ERROR, DENIED keywords and outputs Decompiler Standard summaries.
  Processes log files lazily via IO.binstream without out-of-memory errors.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  @chunk_size 1024

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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle truncation/rotation
      current_pos = if stat.size < last_pos, do: 0, else: last_pos

      if current_pos < stat.size do
        new_pos = process_log(log_path, current_pos)
        %{state | last_byte_pos: new_pos}
      else
        Logger.info("No new traffic logs to audit.")
        state
      end
    else
      Logger.info("Audit log file not found at #{log_path}, skipping audit.")
      state
    end
  end

  defp process_log(log_path, start_pos) do
    file = File.open!(log_path, [:read, :binary])
    :file.position(file, start_pos)

    # Process lazily using reduce
    {_final_chunk, new_pos} = IO.binstream(file, @chunk_size)
    |> Enum.reduce({"", start_pos}, fn chunk, {acc_str, pos} ->
      new_str = acc_str <> chunk
      lines = String.split(new_str, "\n")

      # The last element might be an incomplete line
      {complete_lines, [incomplete_line]} = Enum.split(lines, -1)

      Enum.each(complete_lines, fn line ->
        if String.match?(line, ~r/(CRITICAL|ERROR|DENIED)/) do
          output_decompiler_standard(line)
        end
      end)

      {incomplete_line, pos + byte_size(chunk)}
    end)

    File.close(file)
    new_pos
  end

  defp output_decompiler_standard(snippet) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    output = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET: #{snippet}
    STATUS: ANALYZED
    """

    Logger.warning("\n" <> output)
  end
end
