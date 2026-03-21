defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  Nightly security audit for "Human-in-the-loop" agent traffic, adhering to the
  "Decompiler Standard".

  Reads from `log/agent_traffic.log` directly using file streams.
  Tracks the last byte position to prevent reprocessing old logs.
  """
  use GenServer
  require Logger

  # Nightly run (in milliseconds)
  @interval 24 * 60 * 60 * 1000
  @log_file "log/agent_traffic.log"
  @state_file "log/agent_traffic.pos"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit do
    Logger.info("Starting Nightly Security Audit (Decompiler Standard) on #{@log_file}...")

    ensure_files()

    last_pos = read_last_pos()

    case File.open(@log_file, [:read]) do
      {:ok, file} ->
        :file.position(file, last_pos)

        # We read lines sequentially to evaluate according to standard
        {new_pos, warnings} = process_lines(file, last_pos, [])

        File.close(file)

        write_last_pos(new_pos)

        report_warnings(warnings)

      {:error, reason} ->
        Logger.error("Security Audit could not open #{@log_file}: #{inspect(reason)}")
    end
  end

  defp ensure_files do
    unless File.exists?("log"), do: File.mkdir_p!("log")
    unless File.exists?(@log_file), do: File.touch!(@log_file)
    unless File.exists?(@state_file), do: write_last_pos(0)
  end

  defp read_last_pos do
    case File.read(@state_file) do
      {:ok, content} ->
        case Integer.parse(String.trim(content)) do
          {pos, _} -> pos
          :error -> 0
        end
      {:error, _} -> 0
    end
  end

  defp write_last_pos(pos) do
    File.write!(@state_file, to_string(pos))
  end

  defp process_lines(file, current_pos, warnings) do
    case IO.binread(file, :line) do
      :eof ->
        {current_pos, warnings}
      {:error, _reason} ->
        {current_pos, warnings}
      line ->
        new_warnings = evaluate_line_decompiler_standard(line, warnings)
        new_pos = current_pos + byte_size(line)
        process_lines(file, new_pos, new_warnings)
    end
  end

  defp evaluate_line_decompiler_standard(line, warnings) do
    # Simple check for Decompiler Standard compliance logic
    # Assume lines containing "EVAL" or "SYSTEM" or "ROOT" in human-in-the-loop requires critical review.
    up_line = String.upcase(line)

    cond do
      String.contains?(up_line, "EVAL(") ->
        ["Critical Warning [Decompiler Standard Violation]: EVAL used in agent payload. Line: #{String.trim(line)}" | warnings]
      String.contains?(up_line, "SUDO ") ->
        ["Critical Warning [Security Risk]: SUDO attempt detected. Line: #{String.trim(line)}" | warnings]
      String.contains?(up_line, "UNAUTHORIZED_ACCESS") ->
        ["Warning [Decompiler Standard]: Unauthorized access logged. Line: #{String.trim(line)}" | warnings]
      true ->
        warnings
    end
  end

  defp report_warnings([]) do
    Logger.info("Nightly Security Audit completed cleanly. No human-in-the-loop warnings found.")
  end

  defp report_warnings(warnings) do
    Logger.error("Nightly Security Audit found #{length(warnings)} CRITICAL issues. Summarizing below:")
    Enum.each(warnings, fn w -> Logger.error(" -> " <> w) end)
  end
end
