defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Nightly Security Audits format and summarize their analysis of 'Human-in-the-loop'
  agent traffic according to the project's 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

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

  def perform_audit(%{last_byte_pos: last_pos}) do
    path = Application.get_env(:governance_core, :audit_log_path)

    if is_nil(path) or not File.exists?(path) do
      Logger.info("NightlyAudit: Audit log path not configured or file missing.")
      %{last_byte_pos: last_pos}
    else
      # Check file size for truncation
      stat = File.stat!(path)
      current_pos = if stat.size < last_pos, do: 0, else: last_pos

      {new_pos, findings} = process_log_file(path, current_pos)

      if length(findings) > 0 do
        report = format_report(findings)
        Logger.info("\n" <> report)
      else
        Logger.info("NightlyAudit: No critical findings in traffic.")
      end

      %{last_byte_pos: new_pos}
    end
  end

  defp process_log_file(path, start_pos) do
    File.open!(path, [:read], fn file ->
      :file.position(file, start_pos)

      # Process lazily to prevent OOM
      findings = IO.binstream(file, :line)
      |> Enum.reduce([], fn line, acc ->
        if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
          [String.trim(line) | acc]
        else
          acc
        end
      end)

      {elem(:file.position(file, :cur), 1), Enum.reverse(findings)}
    end)
  end

  defp format_report(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(findings, "\n")

    """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """
  end
end
