defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Nightly Security Audit analyzing human-in-the-loop agent traffic.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
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

  def perform_audit(%{last_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if is_nil(log_path) or not File.exists?(log_path) do
      Logger.warning("Audit log path not configured or file not found.")
      state
    else
      process_log_file(log_path, last_pos)
    end
  end

  defp process_log_file(log_path, last_pos) do
    %{size: current_size} = File.stat!(log_path)

    start_pos = if current_size < last_pos, do: 0, else: last_pos

    {:ok, file} = :file.open(String.to_charlist(log_path), [:read, :binary])
    :file.position(file, start_pos)

    # Process lazily to prevent OOM
    findings =
      IO.binstream(file, :line)
      |> Enum.reduce([], fn line, acc ->
        if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
          [line | acc]
        else
          acc
        end
      end)

    :file.close(file)

    new_pos = File.stat!(log_path).size

    if findings != [] do
      report_findings(Enum.reverse(findings))
    else
      Logger.info("No critical findings in tonight's audit.")
    end

    %{last_pos: new_pos}
  end

  defp report_findings(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("Nightly Audit Report Generated:\n#{report}")
  end
end
