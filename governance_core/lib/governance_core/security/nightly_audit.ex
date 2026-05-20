defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A Nightly Audit process that parses "Human-in-the-loop" agent traffic logs
  every 24 hours, formatting and summarizing critical findings according
  to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
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
  def handle_info(:run_audit, state) do
    new_pos = run_audit(state.last_byte_pos)
    schedule_audit()
    {:noreply, %{state | last_byte_pos: new_pos}}
  end

  defp schedule_audit do
    Process.send_after(self(), :run_audit, @interval)
  end

  defp run_audit(last_byte_pos) do
    Logger.info("Running Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || "priv/agent_traffic.log"

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle file truncation/rotation
      pos =
        if stat.size < last_byte_pos do
          0
        else
          last_byte_pos
        end

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, pos)

          # Process lazily to prevent OOM
          new_pos =
            IO.binstream(file, :line)
            |> Enum.reduce(pos, fn line, _acc ->
              process_line(line)
              # Not precise byte count update per line using Enum.reduce in Elixir due to string encoding,
              # so we'll just read till EOF and get the new position at the end.
              0
            end)

          {:ok, final_pos} = :file.position(file, :cur)
          File.close(file)
          final_pos

        {:error, reason} ->
          Logger.error("Failed to open audit log: #{inspect(reason)}")
          last_byte_pos
      end
    else
      Logger.warning("Audit log file not found at #{log_path}")
      last_byte_pos
    end
  end

  defp process_line(line) do
    upcase_line = String.upcase(line)

    if String.contains?(upcase_line, "CRITICAL") or
         String.contains?(upcase_line, "ERROR") or
         String.contains?(upcase_line, "DENIED") do
      format_finding(line)
    end
  end

  defp format_finding(snippet) do
    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET: #{String.trim(snippet)}
    STATUS: ANALYZED
    ---------------------------------
    """

    Logger.warning("\n" <> report)
  end
end
