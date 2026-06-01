defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze Human-in-the-loop agent traffic.
  """
  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000 # 24 hours

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

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle truncation or log rotation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      if stat.size > read_pos do
        new_pos = process_log(log_path, read_pos)
        %{state | last_byte_pos: new_pos}
      else
        Logger.info("No new traffic to audit.")
        %{state | last_byte_pos: stat.size}
      end
    else
      Logger.warning("Audit log file not found: #{log_path}")
      state
    end
  end

  defp process_log(path, start_pos) do
    file = File.open!(path, [:read, :binary])
    :file.position(file, start_pos)

    # Process stream lazily
    {findings, _} = IO.binstream(file, :line)
    |> Enum.reduce({[], 0}, fn line, {acc_findings, _count} ->
      if String.contains?(line, "CRITICAL") or String.contains?(line, "ERROR") or String.contains?(line, "DENIED") do
        {[String.trim(line) | acc_findings], 0}
      else
        {acc_findings, 0}
      end
    end)

    if not Enum.empty?(findings) do
      report = generate_report(findings)
      Logger.info("Nightly Audit completed. Generated report:\n#{report}")
    else
      Logger.info("Nightly Audit completed. No critical findings.")
    end

    {:ok, new_pos} = :file.position(file, :cur)
    File.close(file)

    new_pos
  end

  defp generate_report(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.reverse(findings) |> Enum.join("\n")

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
