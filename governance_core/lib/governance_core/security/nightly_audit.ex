defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  Audits agent traffic log on a nightly basis, summarizing critical findings per the Decompiler Standard.
  """
  use GenServer
  require Logger

  # Nightly interval (24 hours)
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

  def perform_audit(%{last_byte_pos: last_byte_pos} = state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path)

    if is_nil(log_path) do
      Logger.error("Audit log path not configured in :governance_core application env.")
      state
    else
      if File.exists?(log_path) do
        process_log_file(log_path, last_byte_pos)
      else
        Logger.info("Log file #{log_path} does not exist, nothing to audit.")
        state
      end
    end
  end

  defp process_log_file(file_path, last_pos) do
    stat = File.stat!(file_path)

    current_pos =
      if stat.size < last_pos do
        # File was truncated/rotated
        0
      else
        last_pos
      end

    case File.open(file_path, [:read, :binary]) do
      {:ok, file} ->
        :file.position(file, current_pos)

        snippets =
          IO.binstream(file, :line)
          |> Enum.reduce([], fn line, acc ->
            line_str = to_string(line)
            if String.contains?(line_str, ["CRITICAL", "ERROR", "DENIED"]) do
              [String.trim(line_str) | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()

        {:ok, new_pos} = :file.position(file, :cur)
        File.close(file)

        if length(snippets) > 0 do
          generate_report(snippets)
        else
          Logger.info("No critical security findings in tonight's audit.")
        end

        %{last_byte_pos: new_pos}

      {:error, reason} ->
        Logger.error("Failed to open audit log: #{inspect(reason)}")
        %{last_byte_pos: current_pos}
    end
  end

  defp generate_report(snippets) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    snippet_text = Enum.join(snippets, "\n")

    report = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{timestamp}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET:
    #{snippet_text}
    STATUS: ANALYZED
    """

    Logger.info("Nightly Audit Report Generated:\n#{report}")

    # Normally this might be sent to an admin channel or dashboard
  end
end
