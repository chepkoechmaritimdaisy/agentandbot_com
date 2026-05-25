defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application's MCP endpoint to ensure it remains "Agent-Friendly".
  Checks for:
  - Fast response times (< 1000ms)
  - Valid JSON schema
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
    Logger.info("Starting Continuous AX Audit on /api/mcp...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    url = base_url <> "/api/mcp"

    {time_us, result} = :timer.tc(fn -> check_endpoint(url) end)
    time_ms = time_us / 1000

    cond do
      result == :error ->
        handle_failure("MCP endpoint failed validation or returned an error.")
      time_ms > 1000 ->
        handle_failure("MCP endpoint response time exceeded 1000ms (#{time_ms}ms).")
      true ->
        Logger.info("AX Audit Passed: MCP endpoint is Agent-Friendly.")
    end
  end

  defp check_endpoint(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _json} -> :ok
          {:error, _} -> :error
        end
      _ ->
        :error
    end
  end

  defp handle_failure(reason) do
    Logger.error("AX Audit Failed: #{reason}")
    generate_pr(reason)
  end

  defp generate_pr(reason) do
    title = "🤖 [AX Audit] Automated Fix"

    try do
      # Deduplicate PRs
      case System.cmd("gh", ["pr", "list", "--search", "#{title} in:title state:open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            # No existing PR found, create one
            body = "Automated PR created by AX Audit because: #{reason}"

            case System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--head", "ax-audit-fix", "--base", "main"]) do
              {_out, 0} -> Logger.info("AX Audit automatically generated PR.")
              {error_out, _status} -> Logger.error("Failed to generate PR: #{error_out}")
            end
          else
            Logger.info("AX Audit PR already exists, skipping creation.")
          end
        {_out, _status} ->
          Logger.warning("gh pr list command failed, skipping PR creation.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run gh CLI: #{inspect(e)}")
    end
  end
end
