defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Processes the agent traffic log nightly, summarizing critical 'Human-in-the-loop' traffic
  according to the 'Decompiler Standard'.
  """
  use GenServer
  require Logger

  # 24 hours in ms
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_pos: 0}, name: __MODULE__)
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

  def perform_audit(%{last_pos: last_pos}) do
    Logger.info("Starting Nightly Security Audit...")

    # Retrieve audit log path dynamically from environment configuration
    log_path = Application.get_env(:governance_core, :audit_log_path, "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle potential file truncation/rotation
      actual_pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, actual_pos)

          # Read lines lazily to avoid OOM
          critical_logs =
            IO.binstream(file, :line)
            |> Enum.reduce([], fn line, acc ->
              if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
                [String.trim(line) | acc]
              else
                acc
              end
            end)
            |> Enum.reverse()

          # Determine the new position
          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          if length(critical_logs) > 0 do
            generate_report(critical_logs)
          else
            Logger.info("Nightly Audit complete: No new critical issues found.")
          end

          %{last_pos: new_pos}

        {:error, reason} ->
          Logger.error("Failed to open audit log file: #{inspect(reason)}")
          %{last_pos: actual_pos}
      end
    else
      Logger.info("Audit log file #{log_path} not found. Skipping audit.")
      %{last_pos: last_pos}
    end
  end

  defp generate_report(logs) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet = Enum.join(logs, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("Nightly Security Audit Report Generated:\n#{report}")

    # Also write to a file in priv for historical keeping
    report_path = Path.join(File.cwd!(), "priv/nightly_audit_#{DateTime.utc_now() |> DateTime.to_unix()}.log")
    case File.write(report_path, report) do
      :ok -> :ok
      {:error, reason} -> Logger.error("Failed to write nightly audit report: #{inspect(reason)}")
    end
  end
end
