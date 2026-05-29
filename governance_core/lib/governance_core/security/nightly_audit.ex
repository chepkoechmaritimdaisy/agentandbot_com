defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Every night, analyzes 'Human-in-the-loop' agent traffic logs, summarizing them
  according to the Decompiler Standard.
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
  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{last_byte_pos: last_pos} = state) do
    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, {:bof, read_pos})

          # Process lazily to prevent OOM
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

          # New end of file
          {:ok, new_pos} = :file.position(file, :cur)
          File.close(file)

          if findings != [] do
            generate_report(findings)
          else
            Logger.info("Nightly Audit: No new critical findings.")
          end

          %{state | last_byte_pos: new_pos}

        {:error, reason} ->
          Logger.error("Nightly Audit failed to open log file: #{inspect(reason)}")
          state
      end
    else
      Logger.warning("Nightly Audit: Log path not configured or file missing.")
      state
    end
  end

  defp generate_report(findings) do
    snippet = Enum.join(findings, "\n")
    timestamp = DateTime.utc_now() |> DateTime.to_string()

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    Logger.info("\n#{report}")
  end
end
