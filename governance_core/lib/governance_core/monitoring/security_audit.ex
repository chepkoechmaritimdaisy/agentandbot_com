defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Runs Nightly Security Audits on agent traffic.
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

  def perform_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle file truncation/rotation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, read_pos)

          # Process lines lazily
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

          new_pos = stat.size
          File.close(file)

          generate_report(findings)

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log: #{inspect(reason)}")
          state
      end
    else
      Logger.info("Audit log path not configured or file missing.")
      state
    end
  end

  defp generate_report(findings) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    snippet = if Enum.empty?(findings) do
      "No critical issues found."
    else
      Enum.join(findings)
    end

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("Security Audit Report:\n#{report}")
  end
end
