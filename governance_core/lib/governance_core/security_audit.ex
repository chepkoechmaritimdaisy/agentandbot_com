defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly Security Audit process.
  Analyzes human-in-the-loop agent traffic.
  """
  use GenServer
  require Logger

  # 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    log_file = Keyword.get(opts, :log_file, Path.join(:code.priv_dir(:governance_core), "agent_traffic.log"))

    # Ensure directory and file exists for our track
    File.mkdir_p!(Path.dirname(log_file))
    unless File.exists?(log_file) do
      File.write!(log_file, "")
    end

    schedule_audit()
    {:ok, %{log_file: log_file, last_byte_pos: 0}}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{log_file: log_file, last_byte_pos: last_pos} = state) do
    Logger.info("Running Nightly Security Audit")

    current_size =
      case File.stat(log_file) do
        {:ok, stat} -> stat.size
        _ -> 0
      end

    {read_pos, final_pos} =
      if current_size < last_pos do
        {0, current_size} # Truncated or rotated
      else
        {last_pos, current_size}
      end

    if final_pos > read_pos do
      process_log_file(log_file, read_pos)
    else
      Logger.info("No new log entries to audit.")
    end

    %{state | last_byte_pos: final_pos}
  end

  defp process_log_file(log_file, start_pos) do
    File.open!(log_file, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      # Read lazily
      snippets =
        IO.binstream(file, :line)
        |> Enum.reduce([], fn line, acc ->
          if String.contains?(line, "Human-in-the-loop") and
             (String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED")) do
            [String.trim(line) | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      if length(snippets) > 0 do
        report = generate_report(snippets)
        Logger.info("\n#{report}")
      end
    end)
  end

  defp generate_report(snippets) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet_text = Enum.join(snippets, "\n")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet_text}
    STATUS: ANALYZED
    """
  end
end
