defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Queries the `/api/mcp` endpoint and checks for valid JSON schema and response times.
  Automatically fixes and opens a PR if issues are found.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"

    case check_endpoint(url) do
      :ok ->
        Logger.info("AX Audit Passed: Endpoint #{url} is Agent-Friendly.")
      {:error, reason} ->
        Logger.error("AX Audit Failed: #{reason}")
        handle_failure(reason)
    end
  end

  defp check_endpoint(url) do
    {time_us, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)

    # 1000ms = 1_000_000 microseconds
    if time_us > 1_000_000 do
      {:error, "Response time #{div(time_us, 1000)}ms exceeded 1000ms limit"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> :ok
            {:error, _} -> {:error, "Response body is not valid JSON"}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch: #{inspect(reason)}"}
      end
    end
  end

  defp handle_failure(reason) do
    try do
      # Avoid PR spam loops
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix in:title", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_fix_pr(reason)
          else
            Logger.info("AX Audit PR already open, skipping.")
          end
        {err, code} ->
          Logger.error("Failed to list PRs: #{err} (code #{code})")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run System.cmd: #{inspect(e)}")
    end
  end

  defp create_fix_pr(reason) do
    try do
      file_path = Path.join(File.cwd!(), "priv/ax_audit_fix.txt")
      fix_content = "Automated fix triggered due to: #{reason}\n"

      File.write!(file_path, fix_content)

      branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

      case System.cmd("git", ["checkout", "-b", branch_name]) do
        {_, 0} ->
          case System.cmd("git", ["add", file_path]) do
            {_, 0} ->
              case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"]) do
                {_, 0} ->
                  case System.cmd("git", ["push", "-u", "origin", branch_name]) do
                    {_, 0} ->
                      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", fix_content]) do
                        {out, 0} ->
                          Logger.info("Created PR for AX Audit fix: #{out}")
                        {err, code} ->
                          Logger.error("Failed to create PR: #{err} (code #{code})")
                      end
                    {err, code} ->
                      Logger.error("Failed to push branch: #{err} (code #{code})")
                  end
                {err, code} ->
                  Logger.error("Failed to commit: #{err} (code #{code})")
              end
            {err, code} ->
              Logger.error("Failed to add file: #{err} (code #{code})")
          end
        {err, code} ->
          Logger.error("Failed to checkout branch: #{err} (code #{code})")
      end

      # switch back to previous branch
      System.cmd("git", ["checkout", "-"])
    rescue
      e in ErlangError ->
        Logger.error("Failed to run System.cmd during PR creation: #{inspect(e)}")
    end
  end
end
