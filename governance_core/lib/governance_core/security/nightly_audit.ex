defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  GenServer that runs every 24 hours to analyze the configured audit log for
  CRITICAL, ERROR, or DENIED entries and outputs an analysis following the
  Decompiler Standard.
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

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    path = Application.get_env(:governance_core, :audit_log_path)

    if path && File.exists?(path) do
      try do
        stat = File.stat!(path)

        # Handle log rotation/truncation
        start_pos = if stat.size < last_byte_pos, do: 0, else: last_byte_pos

        File.open(path, [:read, :binary], fn file ->
          :file.position(file, {:bof, start_pos})

          # Lazy stream to prevent OOM
          stream = IO.binstream(file, :line)

          findings = Enum.reduce(stream, [], fn line, acc ->
            str_line = String.trim(line)
            if String.contains?(str_line, ["CRITICAL", "ERROR", "DENIED"]) do
              [str_line | acc]
            else
              acc
            end
          end)

          findings = Enum.reverse(findings)

          if length(findings) > 0 do
            output_decompiler_standard(findings)
          end
        end)

        %{state | last_byte_pos: stat.size}
      rescue
        e ->
          Logger.error("Failed to perform NightlyAudit: #{inspect(e)}")
          state
      end
    else
      Logger.info("Audit log file not found at path: #{inspect(path)}")
      state
    end
  end

  defp output_decompiler_standard(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    ---------------------------------
    """

    Logger.info("NightlyAudit Report:\n#{report}")
  end
end
