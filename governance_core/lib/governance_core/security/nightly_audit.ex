defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  GenServer that reads the human-in-the-loop agent traffic audit log
  nightly, filters for critical events, and outputs a summary formatted
  to the Decompiler Standard.
  """

  use GenServer
  require Logger

  # Nightly interval: 24 hours
  @interval 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first run
    schedule_audit()
    {:ok, %{last_byte_pos: 0}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = process_logs(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp process_logs(%{last_byte_pos: pos} = state) do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      read_pos = if stat.size < pos, do: 0, else: pos

      if stat.size > read_pos do
        new_pos = read_and_analyze(log_path, read_pos)
        %{state | last_byte_pos: new_pos}
      else
        # No new data
        state
      end
    else
      Logger.warning("NightlyAudit: Audit log path not configured or file not found.")
      state
    end
  end

  defp read_and_analyze(file_path, start_pos) do
    case File.open(file_path, [:read]) do
      {:ok, file} ->
        :file.position(file, start_pos)

        # Read lines lazily to prevent OOM
        findings =
          IO.binstream(file, :line)
          |> Enum.reduce([], fn line, acc ->
            if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
              [String.trim(line) | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()

        {:ok, new_pos} = :file.position(file, :cur)
        File.close(file)

        if findings != [] do
          output_decompiler_standard(findings)
        end

        new_pos

      {:error, reason} ->
        Logger.error("NightlyAudit: Failed to open log file #{file_path}: #{inspect(reason)}")
        start_pos
    end
  end

  defp output_decompiler_standard(findings) do
    snippet = Enum.join(findings, "\n")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("\n" <> report)
    # Could also write to a report file or send via email/slack
  end
end
