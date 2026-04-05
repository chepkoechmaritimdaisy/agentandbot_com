defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that runs nightly audits on 'Human-in-the-loop' agent traffic.
  Processes `log/agent_traffic.log` tracking byte position to avoid reprocessing
  and lazy loading lines to avoid OOM.
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
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = run_nightly_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp run_nightly_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit on agent traffic...")

    if File.exists?(@log_file) do
      stat = File.stat!(@log_file)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      if stat.size > read_pos do
        new_pos = process_log_file(@log_file, read_pos)
        %{state | last_byte_pos: new_pos}
      else
        Logger.info("No new agent traffic to audit.")
        state
      end
    else
      Logger.info("Agent traffic log file not found.")
      state
    end
  end

  defp process_log_file(file_path, start_pos) do
    File.open!(file_path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      # Lazily process stream with reduce to avoid OOM
      {summary_data, bytes_read} =
        IO.binstream(file, :line)
        |> Enum.reduce({%{}, 0}, fn line, {acc, bytes} ->
          parsed_line = parse_traffic_line(line)
          new_acc = aggregate_data(acc, parsed_line)
          {new_acc, bytes + byte_size(line)}
        end)

      generate_decompiler_summary(summary_data)

      start_pos + bytes_read
    end)
  end

  defp parse_traffic_line(line) do
    # Placeholder parsing logic
    if String.contains?(line, "human-in-the-loop") do
       :hitl_event
    else
       :normal_event
    end
  end

  defp aggregate_data(acc, :hitl_event) do
    Map.update(acc, :hitl_count, 1, &(&1 + 1))
  end
  defp aggregate_data(acc, _), do: acc

  defp generate_decompiler_summary(data) do
    # Format according to "Decompiler Standard"
    count = Map.get(data, :hitl_count, 0)

    summary = """
    === DECOMPILER STANDARD SECURITY AUDIT ===
    Date: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Human-in-the-loop Interventions: #{count}
    Critical Warnings: #{if count > 10, do: "HIGH VOLUME DETECTED", else: "None"}
    ==========================================
    """

    Logger.info("Nightly Audit Complete:\n" <> summary)

    # In a real scenario, this might email the admin or post to a Slack channel
  end
end
