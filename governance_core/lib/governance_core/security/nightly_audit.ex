defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A Nightly Audit GenServer that analyzes "Human-in-the-loop" agent traffic logs.
  Filters critical keywords and outputs using the Decompiler Standard format.
  """
  use GenServer
  require Logger

  # 24 hours
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

  defp perform_audit(state) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Application.get_env(:governance_core, :audit_log_path) || Path.join(File.cwd!(), "priv/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      last_pos = if stat.size < state.last_byte_pos do
        0 # Handle truncation / log rotation
      else
        state.last_byte_pos
      end

      new_pos = read_and_filter_logs(log_path, last_pos)
      %{state | last_byte_pos: new_pos}
    else
      Logger.warning("Audit log file not found at: #{log_path}")
      state
    end
  end

  defp read_and_filter_logs(log_path, start_pos) do
    File.open(log_path, [:read, :binary], fn file ->
      :file.position(file, start_pos)

      final_pos = IO.binstream(file, :line)
      |> Enum.reduce(start_pos, fn line, current_pos ->
        if contains_critical_keyword?(line) do
          output_decompiler_standard(line)
        end
        current_pos + byte_size(line)
      end)

      final_pos
    end)
    |> case do
      {:ok, final_pos} -> final_pos
      {:error, reason} ->
        Logger.error("Failed to read audit log: #{inspect(reason)}")
        start_pos
    end
  end

  defp contains_critical_keyword?(line) do
    String.contains?(line, "CRITICAL") or
    String.contains?(line, "ERROR") or
    String.contains?(line, "DENIED")
  end

  defp output_decompiler_standard(line) do
    formatted = """
    --- DECOMPILER STANDARD AUDIT ---
    TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    SOURCE: HUMAN_IN_THE_LOOP
    TRAFFIC_SNIPPET: #{String.trim(line)}
    STATUS: ANALYZED
    """

    Logger.info("\n#{formatted}")
  end
end
