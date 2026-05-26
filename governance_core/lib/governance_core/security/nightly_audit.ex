defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze Human-in-the-loop traffic logs,
  summarizing critical findings according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

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

    # Do not hardcode path, fetch dynamically
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      process_log_file(log_path, last_pos, state)
    else
      Logger.info("Audit log path not configured or file missing, skipping Nightly Audit.")
      state
    end
  end

  defp process_log_file(log_path, last_pos, state) do
    current_size = File.stat!(log_path).size

    # Handle log rotation or truncation
    read_pos = if current_size < last_pos, do: 0, else: last_pos

    case File.open(log_path, [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, read_pos)

        # Read lazily to prevent OOM
        findings =
          IO.binstream(file, :line)
          |> Enum.reduce([], fn line, acc ->
            if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
              [line | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()
          |> Enum.join("")

        File.close(file)

        if findings != "" do
          output_decompiler_standard(findings)
        else
          Logger.info("Nightly Audit found no critical traffic.")
        end

        %{state | last_byte_pos: current_size}

      {:error, reason} ->
        Logger.error("Nightly Audit failed to open log file: #{inspect(reason)}")
        state
    end
  end

  defp output_decompiler_standard(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    summary = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{findings}
    STATUS: ANALYZED
    """

    Logger.info("\n" <> summary)
  end
end
