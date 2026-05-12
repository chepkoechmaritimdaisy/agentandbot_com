defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that performs a nightly (24h) security audit on human-in-the-loop
  agent traffic logs. It tracks file position to prevent reprocessing, filters for
  critical findings, and formats a summary according to the Decompiler Standard.
  """
  use GenServer
  require Logger

  # Nightly interval: 24 hours
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
    new_state = perform_nightly_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_nightly_audit(%{last_byte_pos: last_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if log_path && File.exists?(log_path) do
      stat = File.stat!(log_path)

      # Handle log rotation or truncation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      if stat.size > read_pos do
        case File.open(log_path, [:read, :binary]) do
          {:ok, file} ->
            :file.position(file, read_pos)

            # Process stream lazily with Enum.reduce to avoid OOM
            {findings, new_pos} =
              IO.binstream(file, :line)
              |> Enum.reduce({[], read_pos}, fn line, {acc, pos} ->
                new_acc = if is_critical?(line), do: [line | acc], else: acc
                {new_acc, pos + byte_size(line)}
              end)

            File.close(file)

            if findings != [] do
              generate_report(Enum.reverse(findings))
            else
              Logger.info("Nightly Audit complete: No new critical findings.")
            end

            %{state | last_byte_pos: new_pos}

          {:error, reason} ->
            Logger.error("Failed to open audit log: #{inspect(reason)}")
            state
        end
      else
        Logger.info("Nightly Audit complete: No new traffic to analyze.")
        state
      end
    else
      Logger.warning("Audit log path not configured or file does not exist.")
      state
    end
  end

  defp is_critical?(line) do
    String.contains?(line, "CRITICAL") or
    String.contains?(line, "ERROR") or
    String.contains?(line, "DENIED")
  end

  defp generate_report(findings) do
    snippet = Enum.join(findings, "")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet}
    STATUS: ANALYZED
    """

    # We log it here so the admin sees it in the morning
    Logger.info("\n#{report}")
  end
end
