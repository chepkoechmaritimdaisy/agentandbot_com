defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for "Human-in-the-loop" agent traffic.
  Lazily parses dynamic log files to find critical issues and outputs them in Decompiler Standard format.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000

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

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      process_log(log_path, last_byte_pos, state)
    else
      Logger.warning("Audit log path not configured or file missing.")
      state
    end
  end

  defp process_log(log_path, last_byte_pos, state) do
    stat = File.stat!(log_path)
    file_size = stat.size

    # Handle file truncation/rotation
    start_pos = if file_size < last_byte_pos, do: 0, else: last_byte_pos

    if start_pos < file_size do
      File.open(log_path, [:read, :binary], fn file ->
        if start_pos > 0 do
          :file.position(file, start_pos)
        end

        snippets =
          IO.binstream(file, :line)
          |> Enum.reduce([], fn line, acc ->
            if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
              [String.trim(line) | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()

        if not Enum.empty?(snippets) do
          format_and_log_report(snippets)
        end
      end)

      %{state | last_byte_pos: file_size}
    else
      Logger.info("No new logs to audit.")
      state
    end
  end

  defp format_and_log_report(snippets) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet_text = Enum.join(snippets, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet_text}
    STATUS: ANALYZED
    """

    Logger.info("\n" <> report)
  end
end
